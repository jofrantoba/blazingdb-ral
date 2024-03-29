#include "cuDF/generator/sample_generator.h"
#include "cuDF/generator/random_generator.cuh"
#include "CalciteExpressionParsing.h"
#include "utilities/RalColumn.h"
#include <copying.hpp>
#include <types.hpp>
#include "cudf/table.hpp"
#include "cuDF/safe_nvcategory_gather.hpp"

namespace cudf {
namespace generator {

gdf_error generate_sample(std::vector<gdf_column_cpp>& data_frame,
                          std::vector<gdf_column_cpp>& sampled_data,
                          gdf_size_type num_samples) {
    if (data_frame.size() == 0) {
        return GDF_DATASET_EMPTY;
    }

    if (num_samples <= 0) {
        sampled_data = data_frame;
        return GDF_SUCCESS;
    }

    cudf::generator::RandomVectorGenerator<int32_t> generator(0L, data_frame[0].size());
    std::vector<int32_t> arrayIdx = generator(num_samples);

    // Gather
    sampled_data.clear();
    sampled_data.resize(data_frame.size());
    for(size_t i = 0; i < data_frame.size(); i++) {
		auto& input_col = data_frame[i];
		if (input_col.valid())
			sampled_data[i].create_gdf_column(input_col.dtype(), arrayIdx.size(), nullptr, get_width_dtype(input_col.dtype()), input_col.name());
		else
			sampled_data[i].create_gdf_column(input_col.dtype(), arrayIdx.size(), nullptr, nullptr, get_width_dtype(input_col.dtype()), input_col.name());
    }

    cudf::table srcTable = ral::utilities::create_table(data_frame);
    cudf::table destTable = ral::utilities::create_table(sampled_data);

    gdf_column_cpp gatherMap;
    gatherMap.create_gdf_column(GDF_INT32, arrayIdx.size(), arrayIdx.data(), get_width_dtype(GDF_INT32), "");

    // std::cout << "Gather Map\n";
    // print_gdf_column(gatherMap.get_gdf_column());

    cudf::gather(&srcTable, (gdf_index_type*)(gatherMap.get_gdf_column()->data), &destTable);
    ral::init_string_category_if_null(destTable);

    return GDF_SUCCESS;
}

} // namespace generator
} // namespace cudf
