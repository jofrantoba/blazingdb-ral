/*
 * LogicalFilter.cpp
 *
 *  Created on: Jul 20, 2018
 *      Author: felipe
 */

#include "LogicalFilter.h"

#include <stack>
#include <iostream>

#include "CalciteExpressionParsing.h"
#include <nvstrings/NVCategory.h>
#include <nvstrings/NVStrings.h>

#include <blazingdb/io/Library/Logging/Logger.h>
#include "CodeTimer.h"
#include "gdf_wrapper/gdf_wrapper.cuh"

#include "Interpreter/interpreter_cpp.h"
#include "string/nvcategory_util.hpp"
#include "cudf/binaryop.hpp"

typedef struct {
	std::string token;
	column_index_type position;
} operand_position;

column_index_type get_first_open_position(std::vector<bool> & open_positions, column_index_type start_position){
	for(column_index_type index =  start_position;index < open_positions.size(); index++ ){
		if(open_positions[index]){
			open_positions[index] = false;
			return index;
		}
	}
	return -1;
}


/**
 * Creates a physical plan for the expression that can be added to the total plan
 */
void add_expression_to_plan(	blazing_frame & inputs,
		std::vector<gdf_column *>& input_columns, 
		std::string expression,
		column_index_type expression_position,
		column_index_type num_outputs,
		column_index_type num_inputs,
		std::vector<column_index_type> & left_inputs,
		std::vector<column_index_type> & right_inputs,
		std::vector<column_index_type> & outputs,

		std::vector<gdf_binary_operator> & operators,
		std::vector<gdf_unary_operator> & unary_operators,


		std::vector<gdf_scalar> & left_scalars,
		std::vector<gdf_scalar> & right_scalars,
		std::vector<column_index_type> & new_input_indices){

	/*
	 * inputs needed
	 * std::vector<gdf_column> columns,
			std::vector<gdf_column> output_columns,
			short _num_operations,
			std::vector<short> left_input_positions_vec,
			std::vector<short> right_input_positions_vec,
			std::vector<short> output_positions_vec,
			std::vector<short> final_output_positions_vec,
			std::vector<gdf_binary_operator> operators,
			std::vector<gdf_unary_operator> unary_operators,
			std::vector<gdf_scalar> left_scalars, //should be same size as operations with most of them filled in with invalid types unless scalar is used in oepration
			std::vector<gdf_scalar> right_scalars//,
	 */

	//handled in parent
	//std::vector<column_index_type> final_output_positions;
	//std::vector<gdf_column> output_columns;


	column_index_type start_processing_position = num_inputs + num_outputs;

	std::string clean_expression = clean_calcite_expression(expression);

	std::stack<operand_position> operand_stack;
	gdf_scalar dummy_scalar;

	std::vector<bool> processing_space_free(512,true); //a place to stare whether or not a processing space is occupied at any point in time
	for(size_t i = 0; i < start_processing_position; i++){
		processing_space_free[i] = false;
	}
	//pretend they are like registers and we need to know how many registers we need to evaluate this expression

	std::vector<std::string> tokens = get_tokens_in_reverse_order(clean_expression);
	for (size_t token_ind = 0; token_ind < tokens.size(); token_ind++){
		std::string token = tokens[token_ind];

		if(is_operator_token(token)){
			if(is_binary_operator_token(token)){

				std::string left_operand = operand_stack.top().token;
				if(!is_literal(left_operand)){
					if(operand_stack.top().position >= start_processing_position){
						processing_space_free[operand_stack.top().position] = true;
					}
				}
				operand_stack.pop();
				std::string right_operand = operand_stack.top().token;
				if(!is_literal(right_operand)){
					if(operand_stack.top().position >= start_processing_position){
						processing_space_free[operand_stack.top().position] = true;
					}
				}
				operand_stack.pop();

				gdf_binary_operator operation = get_binary_operation(token);
				operators.push_back(operation);
				unary_operators.push_back(BLZ_INVALID_UNARY);

				if(is_literal(left_operand) && is_literal(right_operand)){
					//both are literal have to deduce types, nuts
					//TODO: this is not working yet becuase we have to deduce the types..
					//					gdf_scalar left = get_scalar_from_string(left_operand,inputs.get_column(right_index).dtype());
					//					left_scalars.push_back(left);
					//					gdf_scalar right = get_scalar_from_string(right_operand,inputs.get_column(right_index).dtype());
					//					right_scalars.push_back(left);

					left_inputs.push_back(SCALAR_INDEX); //
				}else if(is_literal(left_operand)){
					size_t right_index = get_index(right_operand);
					// TODO: remove get_type_from_string dirty fix
					// gdf_scalar right = get_scalar_from_string(left_operand,inputs.get_column(get_index(right_operand)).dtype());
					gdf_scalar left = get_scalar_from_string(left_operand,get_type_from_string(left_operand));
					left_scalars.push_back(left);
					right_scalars.push_back(dummy_scalar);

					left_inputs.push_back(left.is_valid ? SCALAR_INDEX : SCALAR_NULL_INDEX);
					right_inputs.push_back(right_index);
				}else if(is_literal(right_operand) && !is_string(right_operand)){
					size_t left_index = get_index(left_operand);
					// TODO: remove get_type_from_string dirty fix
					// gdf_scalar right = get_scalar_from_string(right_operand,inputs.get_column(get_index(left_operand)).dtype());
					gdf_scalar right = get_scalar_from_string(right_operand,get_type_from_string(right_operand));
					right_scalars.push_back(right);
					left_scalars.push_back(dummy_scalar);

					right_inputs.push_back(right.is_valid ? SCALAR_INDEX : SCALAR_NULL_INDEX);
					left_inputs.push_back(left_index);
				}else if(is_literal(right_operand) && is_string(right_operand)){
					right_operand = right_operand.substr(1,right_operand.size()-2);
					size_t left_index = get_index(left_operand);
					gdf_column* left_column = input_columns[left_index];

					int found = static_cast<NVCategory *>(left_column->dtype_info.category)->get_value(right_operand.c_str());

					if(found != -1){
						gdf_data data;
						data.si32 = found;
						gdf_scalar right = {data, GDF_INT32, true};

						right_scalars.push_back(right);
						left_scalars.push_back(dummy_scalar);

						right_inputs.push_back(right.is_valid ? SCALAR_INDEX : SCALAR_NULL_INDEX);
						left_inputs.push_back(left_index);
					}
					else{ //insertar nuevo value, reemplazar columna left

						const char* str = right_operand.c_str();
						const char** strs = &str;
						NVStrings* temp_string = NVStrings::create_from_array(strs, 1);
						NVCategory* new_category = static_cast<NVCategory *>(left_column->dtype_info.category)->add_strings(*temp_string);
						left_column->dtype_info.category = new_category;

						size_t size_to_copy = sizeof(int32_t) * left_column->size;

						CheckCudaErrors(cudaMemcpyAsync(left_column->data,
																						static_cast<NVCategory *>(left_column->dtype_info.category)->values_cptr(),
																						size_to_copy,
																						cudaMemcpyDeviceToDevice));
						
						int found = static_cast<NVCategory *>(left_column->dtype_info.category)->get_value(right_operand.c_str());

						gdf_data data;
						data.si32 = found;
						gdf_scalar right = {data, GDF_INT32, true};

						right_scalars.push_back(right);
						left_scalars.push_back(dummy_scalar);

						right_inputs.push_back(right.is_valid ? SCALAR_INDEX : SCALAR_NULL_INDEX);
						left_inputs.push_back(left_index);
					}
				}else{
					size_t left_index = get_index(left_operand);
					size_t right_index = get_index(right_operand);

					if(input_columns.size() > left_index && input_columns.size() > right_index){
						gdf_column* left_column = input_columns[left_index];
						gdf_column* right_column = input_columns[right_index];

						if(left_column->dtype == GDF_STRING_CATEGORY && right_column->dtype == GDF_STRING_CATEGORY) {
							gdf_column * process_columns[2] = {left_column, right_column};
							gdf_column * output_columns[2] = {left_column, right_column};

							//CUDF_CALL( combine_column_categories(process_columns, output_columns, 2) );
							CUDF_CALL( sync_column_categories(process_columns, output_columns, 2) );

							input_columns[left_index] = output_columns[0];
							input_columns[right_index] = output_columns[1];
						}
					}

					left_inputs.push_back(left_index);
					right_inputs.push_back(right_index);

					left_scalars.push_back(dummy_scalar);
					right_scalars.push_back(dummy_scalar);
				}
			}else if(is_unary_operator_token(token)){
				std::string left_operand = operand_stack.top().token;
				if(!is_literal(left_operand)){
					if(operand_stack.top().position >= start_processing_position){
						processing_space_free[operand_stack.top().position] = true;
					}
				}
				operand_stack.pop();

				gdf_unary_operator operation = get_unary_operation(token);
				operators.push_back(GDF_INVALID_BINARY);
				unary_operators.push_back(operation);

				if(is_literal(left_operand)){

				}else{
					size_t left_index = get_index(left_operand);
					left_inputs.push_back(left_index);
					right_inputs.push_back(-1);

					left_scalars.push_back(dummy_scalar);
					right_scalars.push_back(dummy_scalar);
				}

			}else{
				//uh oh
			}

			if(token_ind == tokens.size() - 1){ // last one
				//write to final output
				outputs.push_back(expression_position + num_inputs);
			}else{
				//write to temp output
				column_index_type output_position = get_first_open_position(processing_space_free,start_processing_position);
				outputs.push_back(output_position);
				//push back onto stack
				operand_stack.push({std::string("$") + std::to_string(output_position),output_position});
			}
		}else{
			if(is_literal(token) || is_string(token)){
				operand_stack.push({token,SCALAR_INDEX});
			}else{
				operand_stack.push({std::string("$" + std::to_string(new_input_indices[get_index(token)])),new_input_indices[get_index(token)]});
			}
		}
	}
}


// processing in reverse we never need to have more than TWO spaces to work in
void evaluate_expression(
		blazing_frame& inputs,
		const std::string& expression,
		gdf_column_cpp& output){

	// make temp a column of size 8 bytes so it can accomodate the largest possible size
	static CodeTimer timer;
	timer.reset();

	// special case when there is nothing to evaluate in the condition expression i.e. LogicalFilter(condition=[$16])
	if(expression[0] == '$'){
		size_t index = get_index(expression);
		if( index >= 0){
			output = inputs.get_column(index).clone();
			return;
		}
	}

	std::string clean_expression = clean_calcite_expression(expression);
	
	std::stack<std::string> operand_stack;

	std::vector<column_index_type> final_output_positions(1);
	std::vector<gdf_column *> output_columns(1);
	output_columns[0] = output.get_gdf_column();
	std::vector<gdf_column *> input_columns;

	std::vector<gdf_dtype> output_type_expressions(1); //contains output types for columns that are expressions, if they are not expressions we skip over it
	output_type_expressions[0] = output.dtype();

	std::vector<bool> input_used_in_expression(inputs.get_size_columns(),false);
	std::vector<std::string> tokens = get_tokens_in_reverse_order(clean_expression);
	for (std::string token : tokens){
		
		if(!is_operator_token(token) && !is_literal(token) && !is_string(token)){
			size_t index = get_index(token);
			input_used_in_expression[index] = true;
		}
	}

	std::vector<column_index_type>  left_inputs;
	std::vector<column_index_type>  right_inputs;
	std::vector<column_index_type>  outputs;

	std::vector<gdf_binary_operator>  operators;
	std::vector<gdf_unary_operator>  unary_operators;


	std::vector<gdf_scalar>  left_scalars;
	std::vector<gdf_scalar>  right_scalars;

	std::vector<column_index_type> new_column_indices(input_used_in_expression.size());
	size_t input_columns_used = 0;
	for(int i = 0; i < input_used_in_expression.size(); i++){
		if(input_used_in_expression[i]){
			new_column_indices[i] = input_columns_used;
			input_columns.push_back( inputs.get_column(i).get_gdf_column());
			input_columns_used++;

		}else{
			new_column_indices[i] = -1; //won't be uesd anyway
		}
	}

	final_output_positions[0] = input_columns_used;


	add_expression_to_plan(	inputs,
						input_columns,
						expression,
						0,
						1,
						input_columns_used,
						left_inputs,
						right_inputs,
						outputs,
						operators,
						unary_operators,
						left_scalars,
						right_scalars,
						new_column_indices);



	perform_operation( output_columns,
				input_columns,
				left_inputs,
				right_inputs,
				outputs,
				final_output_positions,
				operators,
				unary_operators,
				left_scalars,
				right_scalars,
				new_column_indices);


	// output.update_null_count();

	// Library::Logging::Logger().logInfo("-> evaluate_expression took " + std::to_string(timer.getDuration()) + " ms processing expression:\n" + expression);
}
