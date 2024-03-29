#ifndef BLAZINGDB_RAL_DISTRIBUTION_PRIMITIVES_H
#define BLAZINGDB_RAL_DISTRIBUTION_PRIMITIVES_H

#include <vector>
#include "GDFColumn.cuh"
#include "DataFrame.h"
#include "blazingdb/communication/Context.h"
#include "distribution/NodeColumns.h"
#include "distribution/NodeSamples.h"

namespace ral {
namespace distribution {

namespace sampling {

constexpr double THRESHOLD_FOR_SUBSAMPLING = 0.01;

double
calculateSampleRatio(gdf_size_type tableSize);

std::vector<gdf_column_cpp>
generateSample(std::vector<gdf_column_cpp> &table, double ratio);

std::vector<std::vector<gdf_column_cpp>>
generateSamples(std::vector<std::vector<gdf_column_cpp>> &tables,
                const std::vector<double> &               ratios);

std::vector<gdf_column_cpp>
generateSample(std::vector<gdf_column_cpp> &table, std::size_t quantity);

std::vector<std::vector<gdf_column_cpp>>
generateSamples(std::vector<std::vector<gdf_column_cpp>> &input_tables,
                std::vector<std::size_t> &                quantities);

void
normalizeSamples(std::vector<NodeSamples>& samples);

}  // namespace sampling
}  // namespace distribution
}  // namespace ral

namespace ral {
namespace distribution {

namespace {
using Context = blazingdb::communication::Context;
} // namespace

void sendSamplesToMaster(const Context& context, std::vector<gdf_column_cpp>&& samples, std::size_t total_row_size);


std::vector<NodeSamples> collectSamples(const Context& context);

std::vector<gdf_column_cpp> generatePartitionPlans(const Context& context, std::vector<NodeSamples>& samples, std::vector<int8_t>& sortOrderTypes);

void distributePartitionPlan(const Context& context, std::vector<gdf_column_cpp>& pivots);

std::vector<gdf_column_cpp> getPartitionPlan(const Context& context);

/**
 * The implementation of the partition must be changed with the 'split' or 'slice' function in cudf.
 * The current implementation transfer the output of the function 'gdf_multisearch' to the CPU
 * memory and then uses the 'slice' function from gdf_column_cpp (each column) in order to create
 * the partitions.
 *
 * The parameters in the 'gdf_multisearch' function are true for 'find_first_greater', false for
 * 'nulls_appear_before_values' and true for 'use_haystack_length_for_not_found'.
 * It doesn't matter whether the value is not found due to the 'gdf_multisearch' retrieve always
 * the position of the greater value or the size of the column in the worst case.
 * The second parameters is used to maintain the order of the positions of the indexes in the output.
 *
 * Precondition:
 * The size of the nodes will be the same as the number of pivots (in one column) plus one.
 *
 * Example:
 * pivots = { 11, 16 }
 * table = { { 10, 12, 14, 16, 18, 20 } }
 * output = { {10} , {12, 14, 16}, {18, 20} }
 */
std::vector<NodeColumns> partitionData(const Context& context,
                                       std::vector<gdf_column_cpp>& table,
                                       std::vector<int>& searchColIndices,
                                       std::vector<gdf_column_cpp>& pivots,
                                       bool isTableSorted);

void distributePartitions(const Context& context, std::vector<NodeColumns>& partitions);

std::vector<NodeColumns> collectPartitions(const Context& context);

void sortedMerger(std::vector<NodeColumns>& columns, std::vector<int8_t>& sortOrderTypes, std::vector<int>& sortColIndices, blazing_frame& output);

std::vector<gdf_column_cpp> generatePartitionPlansGroupBy(const Context& context, std::vector<NodeSamples>& samples);

void groupByWithoutAggregationsMerger(std::vector<NodeColumns>& groups, const std::vector<int>& groupColIndices, blazing_frame& output);


}  // namespace distribution
}  // namespace ral


namespace ral {
namespace distribution {

/**
 * It uses a hash partition algorithm in order to split a table. Each partition is stored with the corresponding
 * node in a 'NodeColumn' class. It is primary used for join operation, but it can be used for any operation.
 * The input table will be deleted.
 *
 * @param[in] context 'blazingdb::communication::Context' belongs to communication library. It contains
 * information related to the current query.
 * @param[in] table represents the input columns (table) used in the 'join' operation. The table will be deleted.
 * @param[in] columnIndices indices of the columns to be joined.
 * @return std::vector<NodeColumns> represents an array of NodeColumn (@see NodeColumn), which contains
 * a node with their corresponding partition table.
 */
std::vector<NodeColumns> generateJoinPartitions(const Context& context,
                                                std::vector<gdf_column_cpp>& table,
                                                std::vector<int>& columnIndices);

} // namespace distribution
} // namespace ral

#endif  //BLAZINGDB_RAL_DISTRIBUTION_PRIMITIVES_H
