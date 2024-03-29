/*
 * ParquetParser.cpp
 *
 *  Created on: Nov 29, 2018
 *      Author: felipe
 */

#include "ParquetParser.h"
#include <cudf/io_functions.hpp>
#include <cudf/legacy/column.hpp>
#include <blazingdb/io/Util/StringUtil.h>

#include <arrow/io/file.h>
#include <parquet/file_reader.h>
#include <parquet/schema.h>

#include <GDFColumn.cuh>
#include <GDFCounter.cuh>

#include "../Schema.h"
#include "io/data_parser/ParserUtil.h"


namespace ral {
namespace io {

parquet_parser::parquet_parser() {
	// TODO Auto-generated constructor stub

}

parquet_parser::~parquet_parser() {
	// TODO Auto-generated destructor stub
}

void parquet_parser::parse(std::shared_ptr<arrow::io::RandomAccessFile> file,
	const std::string & user_readable_file_handle,
	std::vector<gdf_column_cpp> & columns_out,
	const Schema & schema,
	std::vector<size_t> column_indices){

	if (column_indices.size() == 0){ // including all columns by default
		column_indices.resize(schema.get_num_columns());
		std::iota(column_indices.begin(), column_indices.end(), 0);
	}

	if (file == nullptr){
		columns_out = create_empty_columns(schema.get_names(), schema.get_dtypes(), column_indices);
		return;
	}
	
	if (column_indices.size() > 0){
	
		// Fill data to pq_args
		cudf::io::parquet::reader_options pq_args;
		pq_args.strings_to_categorical = false;
		pq_args.columns.resize(column_indices.size());
		
		for (size_t column_i = 0; column_i < column_indices.size(); column_i++) {
			pq_args.columns[column_i] = schema.get_name(column_indices[column_i]);			
		}

		cudf::io::parquet::reader parquet_reader(file, pq_args);

		cudf::table table_out = parquet_reader.read_all();

		assert(table_out.num_columns() > 0);
		
		columns_out.resize(column_indices.size());
		for(size_t i = 0; i < columns_out.size(); i++){

			if (table_out.get_column(i)->dtype == GDF_STRING){
				NVStrings* strs = static_cast<NVStrings*>(table_out.get_column(i)->data);
				NVCategory* category = NVCategory::create_from_strings(*strs);
				std::string column_name(table_out.get_column(i)->col_name);
				columns_out[i].create_gdf_column(category, table_out.get_column(i)->size, column_name);
				gdf_column_free(table_out.get_column(i));
			} else {
				columns_out[i].create_gdf_column(table_out.get_column(i));
			}			
		}
	}
}

// This function is copied and adapted from cudf
constexpr std::pair<gdf_dtype, gdf_dtype_extra_info> to_dtype(
    parquet::Type::type physical, parquet::LogicalType::type logical) {

	bool strings_to_categorical = false; // parameter used in cudf::read_parquet

  // Logical type used for actual data interpretation; the legacy converted type
  // is superceded by 'logical' type whenever available.
  switch (logical) {
    case parquet::LogicalType::type::UINT_8:
    case parquet::LogicalType::type::INT_8:
      return std::make_pair(GDF_INT8, gdf_dtype_extra_info{TIME_UNIT_NONE});
    case parquet::LogicalType::type::UINT_16:
    case parquet::LogicalType::type::INT_16:
      return std::make_pair(GDF_INT16, gdf_dtype_extra_info{TIME_UNIT_NONE});
    case parquet::LogicalType::type::DATE:
      return std::make_pair(GDF_DATE32, gdf_dtype_extra_info{TIME_UNIT_NONE});
    case parquet::LogicalType::type::TIMESTAMP_MILLIS:
      return std::make_pair(GDF_DATE64, gdf_dtype_extra_info{TIME_UNIT_ms});
    case parquet::LogicalType::type::TIMESTAMP_MICROS:
      return std::make_pair(GDF_DATE64, gdf_dtype_extra_info{TIME_UNIT_us});
    default:
      break;
  }

  // Physical storage type supported by Parquet; controls the on-disk storage
  // format in combination with the encoding type.
  switch (physical) {
    case parquet::Type::type::BOOLEAN:
      return std::make_pair(GDF_BOOL8, gdf_dtype_extra_info{TIME_UNIT_NONE});
    case parquet::Type::type::INT32:
      return std::make_pair(GDF_INT32, gdf_dtype_extra_info{TIME_UNIT_NONE});
    case parquet::Type::type::INT64:
      return std::make_pair(GDF_INT64, gdf_dtype_extra_info{TIME_UNIT_NONE});
    case parquet::Type::type::FLOAT:
      return std::make_pair(GDF_FLOAT32, gdf_dtype_extra_info{TIME_UNIT_NONE});
    case parquet::Type::type::DOUBLE:
      return std::make_pair(GDF_FLOAT64, gdf_dtype_extra_info{TIME_UNIT_NONE});
    case parquet::Type::type::BYTE_ARRAY:
    case parquet::Type::type::FIXED_LEN_BYTE_ARRAY:
      // Can be mapped to GDF_CATEGORY (32-bit hash) or GDF_STRING (nvstring)
      return std::make_pair(strings_to_categorical ? GDF_CATEGORY : GDF_STRING,
                            gdf_dtype_extra_info{TIME_UNIT_NONE});
    case parquet::Type::type::INT96:
      // Convert Spark INT96 timestamp to GDF_DATE64
      return std::make_pair(GDF_DATE64, gdf_dtype_extra_info{TIME_UNIT_ms});
    default:
      break;
  }

  return std::make_pair(GDF_invalid, gdf_dtype_extra_info{TIME_UNIT_NONE});
}

void parquet_parser::parse_schema(std::vector<std::shared_ptr<arrow::io::RandomAccessFile> > files, ral::io::Schema & schema_out)  {

	// gdf_error error = gdf::parquet::read_schema(files, schema);
	std::vector<std::string> column_names;
	std::vector<gdf_dtype> dtypes;
	std::vector<size_t> num_row_groups(files.size());
	
	std::unique_ptr<parquet::ParquetFileReader> parquet_reader = parquet::ParquetFileReader::Open(files[0]);
	std::shared_ptr<parquet::FileMetaData> file_metadata = parquet_reader->metadata();
	int total_columns = file_metadata->num_columns();
	num_row_groups[0] = file_metadata->num_row_groups();
	const parquet::SchemaDescriptor * schema = file_metadata->schema();
	for(int i = 0; i < total_columns; i++){
		const parquet::ColumnDescriptor * column = schema->Column(i);
		column_names.push_back(column->name());
		std::pair<gdf_dtype, gdf_dtype_extra_info> dtype_pair = to_dtype(column->physical_type(), column->logical_type());
		dtypes.push_back(dtype_pair.first);
	}
	parquet_reader->Close();

	for(int file_index = 1; file_index < files.size(); file_index++){
		parquet_reader = parquet::ParquetFileReader::Open(files[file_index]);
		file_metadata = parquet_reader->metadata();
		const parquet::SchemaDescriptor * schema = file_metadata->schema();
		num_row_groups[file_index] = file_metadata->num_row_groups();
		parquet_reader->Close();
	}
	

	// we currently dont support GDF_DATE32 for parquet so lets filter those out
	std::vector<std::string> column_names_out;
	std::vector<gdf_dtype> dtypes_out;
	for (size_t i = 0; i < column_names.size(); i++){
		if (dtypes[i] != GDF_DATE32){
			column_names_out.push_back(column_names[i]);
			dtypes_out.push_back(dtypes[i]);
		}
	}
	std::vector<std::size_t> column_indices(column_names_out.size());
    std::iota(column_indices.begin(), column_indices.end(), 0);

	schema_out = ral::io::Schema(column_names_out,column_indices,dtypes_out,num_row_groups);
}

} /* namespace io */
} /* namespace ral */
