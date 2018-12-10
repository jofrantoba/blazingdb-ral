#include <gtest/gtest.h>



#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include <gdf_wrapper/gdf_wrapper.cuh>
#include "io/data_parser/CSVParser.h"
#include "io/data_provider/UriDataProvider.h"
#include "io/data_parser/DataParser.h"
#include "io/data_provider/DataProvider.h"

#include <DataFrame.h>
#include <fstream>


#include <GDFColumn.cuh>


struct ParseCSVTest : public ::testing::Test {
protected:
	//TODO: I copied this from dtypes_test we should put these utils in one place
	//imn guessing it exists but I am not sure where
	template<typename T>
	void Check(gdf_column_cpp out_col, T *host_output) {
		T *device_output;
		device_output = new T[out_col.size()];
		cudaMemcpy(device_output,
				out_col.data(),
				out_col.size() * sizeof(T),
				cudaMemcpyDeviceToHost);

		for (std::size_t i = 0; i < out_col.size(); i++) {
			ASSERT_TRUE(host_output[i] == device_output[i]);
		}
	}




	template<typename T, typename Functor>
	std::vector<T> get_generated_column(size_t num_rows, size_t column_index,
			Functor & functor){
		std::vector<T> host_column(num_rows);
		for(size_t row_index = 0; row_index  < num_rows; row_index++){
			host_column[row_index] = functor(row_index,column_index);
		}
		return host_column;
	}

};


template<typename Functor>
void generate_csv_file_int32(size_t num_rows, size_t num_cols, std::string path ,Functor & functor){
	//will create a csv file in /tmp folder
	//names will just be col_1 col_2 etc.
	std::ofstream csv_file;
	csv_file.open (path.c_str());


	//iof functor is row_index * ((column_index) * 3);
	//file should look like
	// 0|0|0|0|0
	// 0|3|6|9|12
	// 0|6|12|18|24

	for(size_t row_index = 0; row_index  < num_rows; row_index++){
		if(row_index > 0)	csv_file<<"\n";
		for(size_t column_index = 0; column_index < num_cols; column_index++){
			if(column_index > 0)	csv_file << "|";
			csv_file<< functor (row_index,column_index);
		}

	}

	csv_file.close();

}


TEST_F(ParseCSVTest, parse_small_csv_file_int32) {

	{
		size_t num_rows = 1000;
		size_t num_cols = 5;
		std::vector<gdf_dtype> types(num_cols,GDF_INT32);
		std::vector<std::string> names(num_cols);

		auto cell_generator= [](size_t row_index, size_t column_index) {
			return (int) (row_index * ((column_index) * 3));
		};


		std::string path = "/tmp/small-test.csv";
		generate_csv_file_int32(
				num_rows,num_cols,path,cell_generator);

		std::vector<std::vector<int> > host_data(num_cols);
		std::vector<gdf_column_cpp> columns(num_cols);
		for(size_t column_index = 0; column_index < num_cols; column_index++){
			names[column_index] = std::string("col_") + std::to_string(column_index);
			host_data[column_index] = get_generated_column<int>(
					num_rows, column_index,cell_generator);

		}

		std::vector<Uri> uris(1);
		uris[0] = Uri(path);




		std::vector<bool> include_column(num_cols,true);

		std::unique_ptr<ral::io::data_provider> provider = std::make_unique<ral::io::uri_data_provider>(uris);
		std::unique_ptr<ral::io::data_parser> parser = std::make_unique<ral::io::csv_parser>("|","\n",0,names,types);


		EXPECT_TRUE(provider->has_next());
		parser->parse(provider->get_next(),columns,include_column);

		for(size_t column_index = 0; column_index < num_cols; column_index++){
			Check(columns[column_index], &host_data[column_index][0]);
		}

	}
}



