#include <iostream>
#include <future>
#include <functional>
#include <iterator>
#include <regex>
#include <tuple>
#include <blazingdb/io/Library/Logging/Logger.h>
#include <blazingdb/io/Util/StringUtil.h>
#include "config/GPUManager.cuh"
#include "GroupBy.h"
#include "CodeTimer.h"
#include "CalciteExpressionParsing.h"
#include "distribution/primitives.h"
#include "communication/CommunicationData.h"
#include "ColumnManipulation.cuh"
#include "GDFColumn.cuh"
#include "LogicalFilter.h"
#include "Traits/RuntimeTraits.h"
#include "utilities/RalColumn.h"

#include "cudf/groupby.hpp"
#include "cudf/table.hpp"
#include "cudf/reduction.hpp"
#include <rmm/thrust_rmm_allocator.h>

#include "cuDF/safe_nvcategory_gather.hpp"

namespace ral {
namespace operators {

namespace {
using blazingdb::communication::Context;
} // namespace

const std::string LOGICAL_AGGREGATE_TEXT = "LogicalAggregate";

bool is_aggregate(std::string query_part){
	return (query_part.find(LOGICAL_AGGREGATE_TEXT) != std::string::npos);
}

std::vector<int> get_group_columns(std::string query_part){
	std::string temp_column_string = get_named_expression(query_part, "group");
	if(temp_column_string.size() <= 2){
		return std::vector<int>();
	}

	// Now we have somethig like {0, 1}
	temp_column_string = temp_column_string.substr(1, temp_column_string.length() - 2);
	std::vector<std::string> column_numbers_string = StringUtil::split(temp_column_string, ",");
	std::vector<int> group_column_indices(column_numbers_string.size());
	for(int i = 0; i < column_numbers_string.size();i++){
		group_column_indices[i] = std::stoull(column_numbers_string[i], 0);
	}
	return group_column_indices;
}

cudf::reduction::operators gdf_agg_op_to_reduction_operators(const gdf_agg_op agg_op){
	switch(agg_op){
		case GDF_SUM:
			return cudf::reduction::operators::SUM;
		case GDF_MIN:
			return cudf::reduction::operators::MIN;
		case GDF_MAX:
			return cudf::reduction::operators::MAX; 
		default:
			std::cout<<"ERROR:	Unexpected gdf_agg_op"<<std::endl;
			return cudf::reduction::operators::SUM;
	}
}

cudf::groupby::hash::operators gdf_agg_op_to_groupby_operators(const gdf_agg_op agg_op){
	switch(agg_op){
		case GDF_SUM:
			return cudf::groupby::hash::SUM;
		case GDF_MIN:
			return cudf::groupby::hash::MIN;
		case GDF_MAX:
			return cudf::groupby::hash::MAX; 
		case GDF_COUNT:
			return cudf::groupby::hash::COUNT; 
		case GDF_AVG:
			return cudf::groupby::hash::MEAN; 
		default:
			std::cout<<"ERROR:	Unexpected gdf_agg_op"<<std::endl;
			return cudf::groupby::hash::COUNT;
	}
}

std::vector<gdf_column_cpp> groupby_without_aggregations(std::vector<gdf_column_cpp>& input, const std::vector<int>& group_column_indices){

	gdf_size_type num_group_columns = group_column_indices.size();
	
	gdf_context ctxt;
	ctxt.flag_null_sort_behavior = GDF_NULL_AS_LARGEST; //  Nulls are are treated as largest
	ctxt.flag_groupby_include_nulls = 1; // Nulls are treated as values in group by keys where NULL == NULL (SQL style)

	cudf::table group_by_data_in_table = ral::utilities::create_table(input);
	cudf::table group_by_columns_out_table;

	//We want the index_col_ptr be on the heap because index_col will call delete when it goes out of scope
	gdf_column * index_col_ptr = new gdf_column;
	std::tie(group_by_columns_out_table, *index_col_ptr) = gdf_group_by_without_aggregations(group_by_data_in_table, 
															num_group_columns, group_column_indices.data(), &ctxt);
	gdf_column_cpp index_col;
    index_col.create_gdf_column(index_col_ptr);

	ral::init_string_category_if_null(group_by_columns_out_table);

	std::vector<gdf_column_cpp> output_columns_group(group_by_columns_out_table.num_columns());
	for(int i = 0; i < output_columns_group.size(); i++){
		auto* grouped_col = group_by_columns_out_table.get_column(i);
		grouped_col->col_name = nullptr; // need to do this because gdf_group_by_without_aggregations is not setting the name properly
		output_columns_group[i].create_gdf_column(grouped_col);
	}
	
	std::vector<gdf_column_cpp> grouped_output(num_group_columns);
	for(int i = 0; i < num_group_columns; i++){
		if (input[i].valid())
			grouped_output[i].create_gdf_column(input[i].dtype(), index_col_ptr->size, nullptr, get_width_dtype(input[i].dtype()), input[i].name());
		else
			grouped_output[i].create_gdf_column(input[i].dtype(), index_col_ptr->size, nullptr, nullptr, get_width_dtype(input[i].dtype()), input[i].name());

		materialize_column(output_columns_group[i].get_gdf_column(),
											grouped_output[i].get_gdf_column(),
											index_col_ptr);
	}
	return grouped_output;
}

void single_node_groupby_without_aggregations(blazing_frame& input, std::vector<int>& group_column_indices){

	std::vector<gdf_column_cpp> data_cols_in(input.get_width());
	for(int i = 0; i < input.get_width(); i++){
		data_cols_in[i] = input.get_column(i);
	}
	std::vector<gdf_column_cpp> grouped_table = groupby_without_aggregations(data_cols_in, group_column_indices);

	input.clear();
	input.add_table(grouped_table);
}

void distributed_groupby_without_aggregations(const Context& queryContext, blazing_frame& input, std::vector<int>& group_column_indices){
	using ral::communication::CommunicationData;

	std::vector<gdf_column_cpp> group_columns(group_column_indices.size());
	for(size_t i = 0; i < group_column_indices.size(); i++){
		group_columns[i] = input.get_column(group_column_indices[i]);
	}
	std::vector<gdf_column_cpp> data_cols_in(input.get_width());
	for(int i = 0; i < input.get_width(); i++){
		data_cols_in[i] = input.get_column(i);
	}

	size_t rowSize = input.get_num_rows_in_table(0);

	std::vector<gdf_column_cpp> selfSamples = ral::distribution::sampling::generateSample(group_columns, 0.1);

	auto groupByTask = std::async(std::launch::async,
																[](std::vector<gdf_column_cpp>& input, const std::vector<int>& group_column_indices){
																	ral::config::GPUManager::getInstance().setDevice();
																	return groupby_without_aggregations(input, group_column_indices);
																},
																std::ref(data_cols_in),
																std::ref(group_column_indices));

	std::vector<gdf_column_cpp> partitionPlan;
	if (queryContext.isMasterNode(CommunicationData::getInstance().getSelfNode())) {
		std::vector<ral::distribution::NodeSamples> samples = ral::distribution::collectSamples(queryContext);
    samples.emplace_back(rowSize, CommunicationData::getInstance().getSelfNode(), std::move(selfSamples));

		partitionPlan = ral::distribution::generatePartitionPlansGroupBy(queryContext, samples);

    ral::distribution::distributePartitionPlan(queryContext, partitionPlan);
	}
	else {
		ral::distribution::sendSamplesToMaster(queryContext, std::move(selfSamples), rowSize);

		partitionPlan = ral::distribution::getPartitionPlan(queryContext);
	}

	// Wait for groupByThread
	std::vector<gdf_column_cpp> groupedTable = groupByTask.get();

	std::vector<ral::distribution::NodeColumns> partitions = ral::distribution::partitionData(queryContext, groupedTable, group_column_indices, partitionPlan, false);

	ral::distribution::distributePartitions(queryContext, partitions);

	std::vector<ral::distribution::NodeColumns> partitionsToMerge = ral::distribution::collectPartitions(queryContext);
	auto it = std::find_if(partitions.begin(), partitions.end(), [&](ral::distribution::NodeColumns& el) {
			return el.getNode() == CommunicationData::getInstance().getSelfNode();
		});
	// Could "it" iterator be partitions.end()?
	partitionsToMerge.push_back(std::move(*it));

	ral::distribution::groupByWithoutAggregationsMerger(partitionsToMerge, group_column_indices, input);
}

void aggregations_with_groupby(std::vector<gdf_column_cpp> & group_by_columns, std::vector<gdf_column_cpp> & aggregation_inputs, 
		const std::vector<gdf_agg_op> & agg_ops,  std::vector<gdf_column_cpp> & group_by_output_columns, 
		std::vector<gdf_column_cpp> & aggrgation_output_columns, const std::vector<std::string> & output_column_names) {
	
	cudf::table keys = ral::utilities::create_table(group_by_columns);
	cudf::table values = ral::utilities::create_table(aggregation_inputs);

	std::vector<cudf::groupby::hash::operators> ops(agg_ops.size());
	std::transform(agg_ops.begin(), agg_ops.end(), 
						ops.begin(), [&](const gdf_agg_op& op) {
    	return gdf_agg_op_to_groupby_operators(op);
	});

	cudf::groupby::hash::Options options(false); // options define null behaviour to be SQL style

	cudf::table group_by_output_table;
	cudf::table aggrgation_output_table;
	std::tie(group_by_output_table, aggrgation_output_table) = cudf::groupby::hash::groupby(keys,
                                            values, ops, options);

	group_by_output_columns.resize(group_by_output_table.num_columns());
	for (size_t i = 0; i < group_by_output_columns.size(); i++){
		group_by_output_columns[i].create_gdf_column(group_by_output_table.get_column(i));
		group_by_output_columns[i].set_name(group_by_columns[i].name());
	}

	aggrgation_output_columns.resize(aggrgation_output_table.num_columns());
	for (size_t i = 0; i < aggrgation_output_columns.size(); i++){
		aggrgation_output_columns[i].create_gdf_column(aggrgation_output_table.get_column(i));
		aggrgation_output_columns[i].set_name(output_column_names[i]);
	}
}

void aggregations_without_groupby(const std::vector<gdf_agg_op> & agg_ops, std::vector<gdf_column_cpp> & aggregation_inputs, 
		std::vector<gdf_column_cpp> & output_columns, const std::vector<gdf_dtype> & output_types, const std::vector<std::string> & output_column_names){
	
	for (size_t i = 0; i < agg_ops.size(); i++){
		switch(agg_ops[i]){
			case GDF_SUM:
			case GDF_MIN:
			case GDF_MAX:
				if (aggregation_inputs[i].size() == 0) {
					// Set output_column data to invalid
					gdf_scalar null_value;
					null_value.is_valid = false;
					null_value.dtype = output_types[i];
					output_columns[i].create_gdf_column(null_value, output_column_names[i]);	
					break;
				} else {
					cudf::reduction::operators reduction_op = gdf_agg_op_to_reduction_operators(agg_ops[i]);
					gdf_scalar reduction_out = cudf::reduce(aggregation_inputs[i].get_gdf_column(), reduction_op, output_types[i]);
					output_columns[i].create_gdf_column(reduction_out, output_column_names[i]);
					break;
				}
			case GDF_AVG:
				if (aggregation_inputs[i].size() == 0 || (aggregation_inputs[i].size() == aggregation_inputs[i].null_count())) {
					// Set output_column data to invalid
					gdf_scalar null_value;
					null_value.is_valid = false;
					null_value.dtype = output_types[i];
					output_columns[i].create_gdf_column(null_value, output_column_names[i]);	
					break;
				} else {
					gdf_dtype sum_output_type = get_aggregation_output_type(aggregation_inputs[i].dtype(),GDF_SUM, false);
					gdf_scalar avg_sum_scalar = cudf::reduce(aggregation_inputs[i].get_gdf_column(), cudf::reduction::operators::SUM, sum_output_type);
					long avg_count = aggregation_inputs[i].get_gdf_column()->size - aggregation_inputs[i].get_gdf_column()->null_count;

					assert(output_types[i] == GDF_FLOAT64);
					assert(sum_output_type == GDF_INT64 || sum_output_type == GDF_FLOAT64);
					
					gdf_scalar avg_scalar;
					avg_scalar.dtype = GDF_FLOAT64;
					avg_scalar.is_valid = true;
					if (avg_sum_scalar.dtype == GDF_INT64)
						avg_scalar.data.fp64 = (double)avg_sum_scalar.data.si64/(double)avg_count;
					else
						avg_scalar.data.fp64 = (double)avg_sum_scalar.data.fp64/(double)avg_count;

					output_columns[i].create_gdf_column(avg_scalar, output_column_names[i]);
					break;
				}			
			case GDF_COUNT:
			{
				gdf_scalar reduction_out;
				reduction_out.dtype = GDF_INT64;
				reduction_out.is_valid = true;
				reduction_out.data.si64 = aggregation_inputs[i].get_gdf_column()->size - aggregation_inputs[i].get_gdf_column()->null_count;   
				
				output_columns[i].create_gdf_column(reduction_out, output_column_names[i]);
				break;
			}
			case GDF_COUNT_DISTINCT:
			{
				// TODO not currently supported
				std::cout<<"ERROR: COUNT DISTINCT currently not supported without a group by"<<std::endl;
			}
		}
	}
}

std::vector<gdf_column_cpp> compute_aggregations(blazing_frame& input, std::vector<int>& group_column_indices, std::vector<gdf_agg_op>& aggregation_types, 
											std::vector<std::string>& aggregation_input_expressions, std::vector<std::string>& aggregation_column_assigned_aliases){
	size_t row_size = input.get_num_rows_in_table(0);

	std::vector<gdf_column_cpp> group_by_columns(group_column_indices.size());
	for(size_t i = 0; i < group_column_indices.size(); i++){
		group_by_columns[i] = input.get_column(group_column_indices[i]);
	}

	std::vector<gdf_column_cpp> aggregation_inputs(aggregation_types.size());
	std::vector<gdf_dtype> output_types(aggregation_types.size());
	std::vector<std::string> output_column_names(aggregation_types.size());

	for(size_t i = 0; i < aggregation_types.size(); i++){
		std::string expression = aggregation_input_expressions[i];
		if(contains_evaluation(expression)){
			//we dont knwo what the size of this input will be so allcoate max size
			//TODO de donde saco el nombre de la columna aqui???
			gdf_dtype unused;
			gdf_dtype agg_input_type = get_output_type_expression(&input, &unused, expression);
			aggregation_inputs[i].create_gdf_column(agg_input_type, row_size, nullptr, get_width_dtype(agg_input_type), "");
			evaluate_expression(input, expression, aggregation_inputs[i]);
		}else{
			aggregation_inputs[i] = input.get_column(get_index(expression));
		}

		output_types[i] = get_aggregation_output_type(aggregation_inputs[i].dtype(), aggregation_types[i], group_column_indices.size() != 0);

		// if the aggregation was given an alias lets use it, otherwise we'll name it based on the aggregation and input
		output_column_names[i] = (aggregation_column_assigned_aliases[i] == ""
																			? (aggregator_to_string(aggregation_types[i]) + "(" + aggregation_inputs[i].name() + ")")
																			: aggregation_column_assigned_aliases[i]);
	}

	std::vector<gdf_column_cpp> group_by_output_columns;
	std::vector<gdf_column_cpp> output_columns_aggregations(aggregation_types.size());
	if (group_column_indices.size() == 0) {
		aggregations_without_groupby(aggregation_types, aggregation_inputs, output_columns_aggregations, output_types, output_column_names);
	}else{
		aggregations_with_groupby(group_by_columns, aggregation_inputs, aggregation_types,  group_by_output_columns, 
			output_columns_aggregations, output_column_names);
	}

	// output table is grouped columns and then aggregated columns
	group_by_output_columns.insert(
		group_by_output_columns.end(),
		std::make_move_iterator(output_columns_aggregations.begin()),
		std::make_move_iterator(output_columns_aggregations.end())
	);

	return group_by_output_columns;
}


void aggregationsMerger(std::vector<ral::distribution::NodeColumns>& aggregations, const std::vector<int>& groupColIndices, const std::vector<gdf_agg_op>& aggregationTypes, blazing_frame& output){
  
	// Concat
	size_t totalConcatsOperations = groupColIndices.size() + aggregationTypes.size();
	int outputRowSize = 0;
	std::vector<std::vector<gdf_column*>> columnsToConcatArray(totalConcatsOperations);
	for(size_t i = 0; i < aggregations.size(); i++)	{
		auto& columns = aggregations[i].getColumnsRef();
		if (columns[0].size() == 0) {
			continue;
		}
		outputRowSize += columns[0].size();

		assert(columns.size() == totalConcatsOperations);
		for(size_t j = 0; j < totalConcatsOperations; j++)
		{	
			// std::cout<<"aggregationsMerger iteration "<<j<<std::endl;
			// print_gdf_column(columns[j].get_gdf_column());
			columnsToConcatArray[j].push_back(columns[j].get_gdf_column());
		}
	}

	if (outputRowSize == 0)	{
		output.clear();
		std::vector<gdf_column_cpp> output_table = aggregations[0].getColumnsRef();
		output.add_table(std::move(output_table));
		return;
	}
  
	std::vector<gdf_column_cpp> concatAggregations(totalConcatsOperations);
	for(size_t i = 0; i < concatAggregations.size(); i++)
	{
		auto* tempGdfCol = columnsToConcatArray[i][0];
		concatAggregations[i].create_gdf_column(tempGdfCol->dtype, outputRowSize, nullptr, get_width_dtype(tempGdfCol->dtype), std::string(tempGdfCol->col_name));
		CUDF_CALL( gdf_column_concat(concatAggregations[i].get_gdf_column(),
									columnsToConcatArray[i].data(),
									columnsToConcatArray[i].size()) );
	}

	
  	// Do aggregations
	std::vector<gdf_column_cpp> groupByColumns(groupColIndices.size());
	for(size_t i = 0; i < groupColIndices.size(); i++){
		groupByColumns[i] = concatAggregations[groupColIndices[i]];
	}

	// when we are merging COUNT aggregations, we want to SUM them, not use COUNT
	std::vector<gdf_agg_op> modAggregationTypes(aggregationTypes.size());
	for(size_t i = 0; i < aggregationTypes.size(); i++){
		modAggregationTypes[i] = aggregationTypes[i] == GDF_COUNT ? GDF_SUM : aggregationTypes[i];
	}

	
	std::vector<gdf_column_cpp> aggregatedColumns(modAggregationTypes.size());
	std::vector<gdf_column_cpp> aggregation_inputs(modAggregationTypes.size());
	std::vector<gdf_dtype> aggregation_dtypes(modAggregationTypes.size());
	std::vector<std::string> aggregation_names(modAggregationTypes.size());
	for(size_t i = 0; i < modAggregationTypes.size(); i++){
		aggregation_inputs[i] = concatAggregations[groupColIndices.size() + i];
		aggregation_dtypes[i] = aggregation_inputs[i].dtype();
		aggregation_names[i] = aggregation_inputs[i].name();
	}

	std::vector<gdf_column_cpp> groupedColumns;
	std::vector<gdf_column_cpp> output_columns_aggregations(modAggregationTypes.size());
	if (groupColIndices.size() == 0) {
		aggregations_without_groupby(modAggregationTypes, aggregation_inputs, aggregatedColumns, aggregation_dtypes, aggregation_names);
	}else{
		aggregations_with_groupby(groupByColumns, aggregation_inputs, modAggregationTypes,  groupedColumns, 
			aggregatedColumns, aggregation_names);
	}

	std::vector<gdf_column_cpp> outputTable(std::move(groupedColumns));
	outputTable.insert(
		outputTable.end(),
		std::make_move_iterator(aggregatedColumns.begin()),
		std::make_move_iterator(aggregatedColumns.end())
	);

  	output.clear();
	output.add_table(outputTable);
}


void single_node_aggregations(blazing_frame& input, std::vector<int>& group_column_indices, std::vector<gdf_agg_op>& aggregation_types, std::vector<std::string>& aggregation_input_expressions, std::vector<std::string>& aggregation_column_assigned_aliases) {
	std::vector<gdf_column_cpp> aggregatedTable = compute_aggregations(input,
																																		group_column_indices,
																																		aggregation_types,
																																		aggregation_input_expressions,
																																		aggregation_column_assigned_aliases);

	input.clear();
	input.add_table(aggregatedTable);
}

void distributed_aggregations_with_groupby(const Context& queryContext, blazing_frame& input, std::vector<int>& group_column_indices, std::vector<gdf_agg_op>& aggregation_types, std::vector<std::string>& aggregation_input_expressions, std::vector<std::string>& aggregation_column_assigned_aliases) {
	using ral::communication::CommunicationData;

	std::vector<gdf_column_cpp> group_columns(group_column_indices.size());
	for(size_t i = 0; i < group_column_indices.size(); i++){
		group_columns[i] = input.get_column(group_column_indices[i]);
	}

	size_t rowSize = input.get_num_rows_in_table(0);

	std::vector<gdf_column_cpp> selfSamples = ral::distribution::sampling::generateSample(group_columns, 0.1);

	// auto aggregationTask = std::async(std::launch::async,
	// 																	[](blazing_frame& input, std::vector<int>& group_column_indices, std::vector<gdf_agg_op>& aggregation_types, std::vector<std::string>& aggregation_input_expressions, std::vector<std::string>& aggregation_column_assigned_aliases){
	// 																		ral::config::GPUManager::getInstance().setDevice();
	// 																		return compute_aggregations(input, group_column_indices, aggregation_types, aggregation_input_expressions, aggregation_column_assigned_aliases);
	// 																	},
	// 																	std::ref(input),
	// 																	std::ref(group_column_indices),
	// 																	std::ref(aggregation_types),
	// 																	std::ref(aggregation_input_expressions),
	// 																	std::ref(aggregation_column_assigned_aliases));

	std::vector<gdf_column_cpp> partitionPlan;
	if (queryContext.isMasterNode(CommunicationData::getInstance().getSelfNode())) {
		std::vector<ral::distribution::NodeSamples> samples = ral::distribution::collectSamples(queryContext);
    samples.emplace_back(rowSize, CommunicationData::getInstance().getSelfNode(), std::move(selfSamples));

		partitionPlan = ral::distribution::generatePartitionPlansGroupBy(queryContext, samples);

    ral::distribution::distributePartitionPlan(queryContext, partitionPlan);
	}
	else {
		ral::distribution::sendSamplesToMaster(queryContext, std::move(selfSamples), rowSize);

		partitionPlan = ral::distribution::getPartitionPlan(queryContext);
	}

	// Wait for aggregationThread
	std::vector<gdf_column_cpp> aggregatedTable = compute_aggregations(input, group_column_indices, aggregation_types, aggregation_input_expressions, aggregation_column_assigned_aliases);//aggregationTask.get();

	std::vector<int> groupColumnIndices(group_column_indices.size());
  std::iota(groupColumnIndices.begin(), groupColumnIndices.end(), 0);

	std::vector<ral::distribution::NodeColumns> partitions = ral::distribution::partitionData(queryContext, aggregatedTable, groupColumnIndices, partitionPlan, false);

	ral::distribution::distributePartitions(queryContext, partitions);

	std::vector<ral::distribution::NodeColumns> partitionsToMerge = ral::distribution::collectPartitions(queryContext);
	auto it = std::find_if(partitions.begin(), partitions.end(), [&](ral::distribution::NodeColumns& el) {
			return el.getNode() == CommunicationData::getInstance().getSelfNode();
		});
	// Could "it" iterator be partitions.end()?
	partitionsToMerge.push_back(std::move(*it));

	aggregationsMerger(partitionsToMerge, groupColumnIndices, aggregation_types, input);
}

void distributed_aggregations_without_groupby(const Context& queryContext, blazing_frame& input, std::vector<int>& group_column_indices, std::vector<gdf_agg_op>& aggregation_types, std::vector<std::string>& aggregation_input_expressions, std::vector<std::string>& aggregation_column_assigned_aliases) {
	using ral::communication::CommunicationData;

	std::vector<gdf_column_cpp> aggregatedTable = compute_aggregations(input,
																																		group_column_indices,
																																		aggregation_types,
																																		aggregation_input_expressions,
																																		aggregation_column_assigned_aliases);

	if (queryContext.isMasterNode(CommunicationData::getInstance().getSelfNode())) {
		std::vector<ral::distribution::NodeColumns> partitionsToMerge = ral::distribution::collectPartitions(queryContext);
		partitionsToMerge.emplace_back(CommunicationData::getInstance().getSelfNode(), std::move(aggregatedTable));

		std::vector<int> groupColumnIndices(group_column_indices.size());
		std::iota(groupColumnIndices.begin(), groupColumnIndices.end(), 0);
		aggregationsMerger(partitionsToMerge, groupColumnIndices, aggregation_types, input);
	}else{
		std::vector<ral::distribution::NodeColumns> selfPartition;
		selfPartition.emplace_back(queryContext.getMasterNode(), std::move(aggregatedTable));
		ral::distribution::distributePartitions(queryContext, selfPartition);

		input.empty_columns(); // here we are clearing the input, because since there are no group bys, there will only be one result, which will be with the master node

	}
}

void process_aggregate(blazing_frame& input, std::string query_part, const Context* queryContext){
	/*
	 * 			String sql = "select sum(e), sum(z), x, y from hr.emps group by x , y";
	 * 			generates the following calcite relational algebra
	 * 			LogicalProject(EXPR$0=[$2], EXPR$1=[$3], x=[$0], y=[$1])
	 * 	  	  		LogicalAggregate(group=[{0, 1}], EXPR$0=[SUM($2)], EXPR$1=[SUM($3)])
	 *   				LogicalProject(x=[$0], y=[$1], e=[$3], z=[$2])
	 *     					EnumerableTableScan(table=[[hr, emps]])
	 *
	 * 			As you can see the project following aggregate expects the columns to be grouped by to appear BEFORE the expressions
	 */

	// Get groups
	auto rangeStart = query_part.find("(");
	auto rangeEnd = query_part.rfind(")") - rangeStart - 1;
	std::string combined_expression = query_part.substr(rangeStart + 1, rangeEnd - 1);

	std::vector<int> group_column_indices = get_group_columns(combined_expression);

	// Get aggregations
	std::vector<gdf_agg_op> aggregation_types;
	std::vector<std::string> aggregation_input_expressions;
	std::vector<std::string> aggregation_column_assigned_aliases;
	std::vector<std::string> expressions = get_expressions_from_expression_list(combined_expression);
	for(std::string expr : expressions){
		std::string expression = std::regex_replace(expr, std::regex("^ +| +$|( ) +"), "$1");
		if (expression.find("group=") == std::string::npos)
		{
			gdf_agg_op operation = get_aggregation_operation(expression);
			aggregation_types.push_back(operation);
			aggregation_input_expressions.push_back(get_string_between_outer_parentheses(expression));

			// if the aggregation has an alias, lets capture it here, otherwise we'll figure out what to call the aggregation based on its input
			if (expression.find("EXPR$") == 0)
				aggregation_column_assigned_aliases.push_back("");
			else
				aggregation_column_assigned_aliases.push_back(expression.substr(0, expression.find("=[")));
		}
	}

	if (aggregation_types.size() == 0) {
		if (!queryContext || queryContext->getTotalNodes() <= 1) {
			single_node_groupby_without_aggregations(input, group_column_indices);
		} else{
			distributed_groupby_without_aggregations(*queryContext, input, group_column_indices);
		}
	} else{
		if (!queryContext || queryContext->getTotalNodes() <= 1) {
				single_node_aggregations(input, group_column_indices, aggregation_types, aggregation_input_expressions, aggregation_column_assigned_aliases);
		} else {
				if (group_column_indices.size() == 0) {
					distributed_aggregations_without_groupby(*queryContext, input, group_column_indices, aggregation_types, aggregation_input_expressions, aggregation_column_assigned_aliases);
				} else {
					distributed_aggregations_with_groupby(*queryContext, input, group_column_indices, aggregation_types, aggregation_input_expressions, aggregation_column_assigned_aliases);
				}
		}
	}
}

}  // namespace operators
}  // namespace ral
