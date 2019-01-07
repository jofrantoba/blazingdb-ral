/*
 ============================================================================
 Name        : testing-libgdf.cu
 Author      : felipe
 Version     :
 Copyright   : Your copyright notice
 Description : MVP
 ============================================================================
 */

#include <cuda_runtime.h>
#include <memory>
#include <algorithm>
#include <thread>
#include "CalciteInterpreter.h"
#include "ResultSetRepository.h"
#include "DataFrame.h"
#include "Utils.cuh"
#include "Types.h"
#include <cuda_runtime.h>

#include "gdf_wrapper/gdf_wrapper.cuh"

#include <tuple>

#include <blazingdb/protocol/api.h>
#include <blazingdb/protocol/message/messages.h>
#include <blazingdb/protocol/message/interpreter/messages.h>
#include <blazingdb/protocol/message/io/file_system.h>
#include "ral-message.cuh"


using namespace blazingdb::protocol;

#include <blazingdb/io/Util/StringUtil.h>

#include <blazingdb/io/FileSystem/HadoopFileSystem.h>
#include <blazingdb/io/FileSystem/S3FileSystem.h>
#include <blazingdb/io/FileSystem/FileSystemRepository.h>
#include <blazingdb/io/FileSystem/FileSystemCommandParser.h>
#include <blazingdb/io/FileSystem/FileSystemManager.h>
#include <blazingdb/io/Config/BlazingContext.h>
#include <blazingdb/io/Library/Logging/Logger.h>
#include <blazingdb/io/Library/Logging/CoutOutput.h>
#include "blazingdb/io/Library/Logging/ServiceLogging.h"

#include "CalciteExpressionParsing.h"
#include "io/data_parser/CSVParser.h"
#include "io/data_parser/ParquetParser.h"

#include "io/data_provider/UriDataProvider.h"
#include "io/data_parser/DataParser.h"
#include "io/data_provider/DataProvider.h"

#include "Config/Config.h"

#include "CodeTimer.h"

const Path FS_NAMESPACES_FILE("/tmp/file_system.bin");
using result_pair = std::pair<Status, std::shared_ptr<flatbuffers::DetachedBuffer>>;
using FunctionType = result_pair (*)(uint64_t, Buffer&& buffer);
  
static result_pair  registerFileSystem(uint64_t accessToken, Buffer&& buffer) {
  std::cout << "registerFileSystem: " << accessToken << std::endl;
  blazingdb::message::io::FileSystemRegisterRequestMessage message(buffer.data());

  FileSystemConnection fileSystemConnection;
  Path root("/");
  const std::string authority =  message.getAuthority();
  if (message.isLocal()) {
    fileSystemConnection = FileSystemConnection(FileSystemType::LOCAL);
  } else if (message.isHdfs()) {
    auto hdfs = message.getHdfs();
    fileSystemConnection = FileSystemConnection(hdfs.host, hdfs.port, hdfs.user, (HadoopFileSystemConnection::DriverType)hdfs.driverType, hdfs.kerberosTicket);
  } else if (message.isS3()) {
    auto s3 = message.getS3();
    fileSystemConnection = FileSystemConnection(s3.bucketName, ( S3FileSystemConnection::EncryptionType )s3.encryptionType, s3.kmsKeyAmazonResourceName, s3.accessKeyId, s3.secretKey, s3.sessionToken);
  }
  root = message.getRoot();
  if (root.isValid() == false) {
    std::cout << "something went wrong when registering filesystem ..." << std::endl;
    ResponseErrorMessage errorMessage{ std::string{ "ERROR: Invalid root provided when registering file system"} };
    return std::make_pair(Status_Error, errorMessage.getBufferData());
  }
  FileSystemEntity fileSystemEntity(authority, fileSystemConnection, root);
  bool ok = BlazingContext::getInstance()->getFileSystemManager()->deregisterFileSystem(authority);
  ok = BlazingContext::getInstance()->getFileSystemManager()->registerFileSystem(fileSystemEntity);
	if (ok) { // then save the fs
		const FileSystemRepository fileSystemRepository(FS_NAMESPACES_FILE, true);
		const bool saved = fileSystemRepository.add(fileSystemEntity);
		if (saved == false) {
			std::cout << "WARNING: could not save the registered file system into ... the data file uri ..."; //TODO percy error message
		}
	} else {
   	  std::cout << "something went wrong when registering filesystem ..." << std::endl;
      ResponseErrorMessage errorMessage{ std::string{"ERROR: Something went wrong when registering file system"} };
      return std::make_pair(Status_Error, errorMessage.getBufferData());
	}
  ZeroMessage response{};
  return std::make_pair(Status_Success, response.getBufferData());
}

static result_pair  deregisterFileSystem(uint64_t accessToken, Buffer&& buffer)  {
  std::cout << "deregisterFileSystem: " << accessToken << std::endl;
  blazingdb::message::io::FileSystemDeregisterRequestMessage message(buffer.data());
  auto authority =  message.getAuthority();
  if (authority.empty() == true) {
     ResponseErrorMessage errorMessage{ std::string{"derigistering an empty authority"} };
     return std::make_pair(Status_Error, errorMessage.getBufferData());
  }
  const bool ok = BlazingContext::getInstance()->getFileSystemManager()->deregisterFileSystem(authority);
  if (ok) { // then save the fs
    const FileSystemRepository fileSystemRepository(FS_NAMESPACES_FILE, true);
    const bool deleted = fileSystemRepository.deleteByAuthority(authority);
    if (deleted == false) {
      std::cout << "WARNING: could not delete the registered file system into ... the data file uri ..."; //TODO percy error message
    }
  }
  ZeroMessage response{};
  return std::make_pair(Status_Success, response.getBufferData());
}


query_token_t loadParquetAndInsertToResultRepository(std::string path, connection_id_t connection) {
	std::cout<<"loadParquet\n";

	query_token_t token = result_set_repository::get_instance().register_query(connection); //register the query so we can receive result requests for it
  Path  csvFile(path);
	Uri directory(csvFile.getParentPath().toString());
  const bool existsParquetDir = BlazingContext::getInstance()->getFileSystemManager()->exists(directory);
	const bool isS3Dir = (directory.getFileSystemType() == FileSystemType::S3);
	if ((existsParquetDir == false) && (isS3Dir == false)) {
    auto error = "parquet table folder doesn't exists: " + directory.toString(false);
    throw std::runtime_error{error};
  }

	std::thread t = std::thread([=]{
    CodeTimer blazing_timer;

		std::vector<Uri> uris(1);
		uris[0] = Uri(path);

		auto provider = std::make_unique<ral::io::uri_data_provider>(uris);
		auto parser = std::make_unique<ral::io::parquet_parser>();
		provider->has_next();

		size_t num_cols = 0; // how many columns this file has?
		std::vector<bool> include_column(num_cols, true);

		std::vector<gdf_column_cpp> columns;
		parser->parse(provider->get_next(), columns);

    blazing_frame output_frame;
  	output_frame.add_table(columns);

		double duration = blazing_timer.getDuration();
		result_set_repository::get_instance().update_token(token, output_frame, duration);
	});
	t.detach();
	return token;
}

static result_pair loadParquetSchema(uint64_t accessToken, Buffer&& buffer) {
 
  blazingdb::message::io::LoadParquetFileRequestMessage message(buffer.data());

  uint64_t resultToken = 0L;
  try {
    // @todo, what about other parameters
    resultToken = loadParquetAndInsertToResultRepository(message.fileSchema()->path, accessToken);

  } catch (std::exception& error) {
     std::cout << error.what() << std::endl;
     ResponseErrorMessage errorMessage{ std::string{error.what()} };
     return std::make_pair(Status_Error, errorMessage.getBufferData());
  }
  interpreter::NodeConnectionDTO nodeInfo {
      .path = "ipc:///tmp/ral.socket",
      .type = NodeConnectionType {NodeConnectionType_IPC}
  };
  interpreter::ExecutePlanResponseMessage responsePayload{resultToken, nodeInfo};
  return std::make_pair(Status_Success, responsePayload.getBufferData());
}

query_token_t loadCsvAndInsertToResultRepository(std::string path, std::vector<std::string> names, std::vector<gdf_dtype> dtypes, std::string delimiter, std::string line_terminator, int skip_rows, connection_id_t connection) {
	std::cout<<"loadCsv\n";

	query_token_t token = result_set_repository::get_instance().register_query(connection); //register the query so we can receive result requests for it
  Path  csvFile(path);
	Uri directory(csvFile.getParentPath().toString());
  const bool existsParquetDir = BlazingContext::getInstance()->getFileSystemManager()->exists(directory);
	const bool isS3Dir = (directory.getFileSystemType() == FileSystemType::S3);
	if ((existsParquetDir == false) && (isS3Dir == false)) {
    auto error = "csv table folder doesn't exists: " + directory.toString(false);
    throw std::runtime_error{error};
  }
	std::thread t = std::thread([=]{
		CodeTimer blazing_timer;

		std::vector<Uri> uris(1);
		uris[0] = Uri(path);

		auto provider = std::make_unique<ral::io::uri_data_provider>(uris);
		auto parser = std::make_unique<ral::io::csv_parser>(delimiter, line_terminator, skip_rows, names, dtypes);
		provider->has_next();

		size_t num_cols = names.size();
		std::vector<bool> include_column(num_cols, true);

		std::vector<gdf_column_cpp> columns;
		parser->parse(provider->get_next(), columns, include_column);

    blazing_frame output_frame;
  	output_frame.add_table(columns);

		double duration = blazing_timer.getDuration();
		result_set_repository::get_instance().update_token(token, output_frame, duration);
	 });
	 t.detach();
	return token;
}

static result_pair loadCsvSchema(uint64_t accessToken, Buffer&& buffer) {
  blazingdb::message::io::LoadCsvFileRequestMessage message(buffer.data());

  std::vector<gdf_dtype> types;
  auto schema = message.fileSchema();
  for(auto val : schema->dtypes)
    types.push_back( (gdf_dtype) val );

  uint64_t resultToken = 0L;
  try {
    resultToken = loadCsvAndInsertToResultRepository(schema->path, schema->names, types, schema->delimiter, schema->line_terminator, schema->skip_rows, accessToken);
  } catch (std::exception& error) {
     std::cout << error.what() << std::endl;
     ResponseErrorMessage errorMessage{ std::string{error.what()} };
     return std::make_pair(Status_Error, errorMessage.getBufferData());
  }
  interpreter::NodeConnectionDTO nodeInfo {
      .path = "ipc:///tmp/ral.socket",
      .type = NodeConnectionType {NodeConnectionType_IPC}
  };
  interpreter::ExecutePlanResponseMessage responsePayload{resultToken, nodeInfo};
  return std::make_pair(Status_Success, responsePayload.getBufferData());
}

using result_pair = std::pair<Status, std::shared_ptr<flatbuffers::DetachedBuffer>>;
using FunctionType = result_pair (*)(uint64_t, Buffer&& buffer);

static result_pair closeConnectionService(uint64_t accessToken, Buffer&& requestPayloadBuffer) {
  std::cout << "accessToken: " << accessToken << std::endl;

  try {
	result_set_repository::get_instance().remove_all_connection_tokens(accessToken);
  } catch (std::runtime_error &error) {
     std::cout << error.what() << std::endl;
     ResponseErrorMessage errorMessage{ std::string{error.what()} };
     return std::make_pair(Status_Error, errorMessage.getBufferData());
  }

  ZeroMessage response{};
  return std::make_pair(Status_Success, response.getBufferData());
}

static result_pair getResultService(uint64_t accessToken, Buffer&& requestPayloadBuffer) {
  std::cout << "accessToken: " << accessToken << std::endl;

  interpreter::GetResultRequestMessage request(requestPayloadBuffer.data());
  std::cout << "resultToken: " << request.getResultToken() << std::endl;


  // remove from repository using accessToken and resultToken
  std::tuple<blazing_frame, double> result = result_set_repository::get_instance().get_result(accessToken, request.getResultToken());

  //TODO ojo el result siempre es una sola tabla por eso indice 0
  const int rows = std::get<0>(result).get_columns()[0][0].size();

  interpreter::BlazingMetadataDTO  metadata = {
    .status = "OK",
    .message = "metadata message",
    .time = std::get<1>(result),
    .rows = rows
  };
  std::vector<std::string> fieldNames;
  std::vector<::gdf_dto::gdf_column> values;

  //TODO WARNING why 0 why multitables?
  for(int i = 0; i < std::get<0>(result).get_columns()[0].size(); ++i) {
	  fieldNames.push_back(std::get<0>(result).get_columns()[0][i].name());
    
    std::cout << "col_name: " << std::get<0>(result).get_columns()[0][i].name() << std::endl;

	  auto data = libgdf::BuildCudaIpcMemHandler(std::get<0>(result).get_columns()[0][i].get_gdf_column()->data);
	  auto valid = libgdf::BuildCudaIpcMemHandler(std::get<0>(result).get_columns()[0][i].get_gdf_column()->valid);

	  auto col = ::gdf_dto::gdf_column {
	        .data = data,
	        .valid = valid,
	        .size = std::get<0>(result).get_columns()[0][i].size(),
	        .dtype = (gdf_dto::gdf_dtype)std::get<0>(result).get_columns()[0][i].dtype(),
	        .null_count = std::get<0>(result).get_columns()[0][i].null_count(),
	        .dtype_info = gdf_dto::gdf_dtype_extra_info {
	          .time_unit = (gdf_dto::gdf_time_unit)0,
	        }
	    };

	  values.push_back(col);
  }

//  // todo: remove hardcode by creating the resulset vector
//  gdf_column_cpp column = result.get_columns()[0][0];
//	std::cout<<"getResultService\n";
//  print_gdf_column(column.get_gdf_column());
//  std::cout<<"end:getResultService\n";
//
//  auto data = libgdf::BuildCudaIpcMemHandler(column.get_gdf_column()->data);
//  auto valid = libgdf::BuildCudaIpcMemHandler(column.get_gdf_column()->valid);
//
//  std::vector<::gdf_dto::gdf_column> values = {
//    ::gdf_dto::gdf_column {
//        .data = data,
//        .valid = valid,
//        .size = column.size(),
//        .dtype = (gdf_dto::gdf_dtype)column.dtype(),
//        .null_count = column.null_count(),
//        .dtype_info = gdf_dto::gdf_dtype_extra_info {
//          .time_unit = (gdf_dto::gdf_time_unit)0,
//        }
//    }
//  };

interpreter::GetResultResponseMessage responsePayload(metadata, fieldNames, values);
  std::cout << "**before return data frame\n" << std::flush;
  return std::make_pair(Status_Success, responsePayload.getBufferData());
}

static result_pair freeResultService(uint64_t accessToken, Buffer&& requestPayloadBuffer) {
   std::cout << "freeResultService: " << accessToken << std::endl;

  interpreter::GetResultRequestMessage request(requestPayloadBuffer.data());
  std::cout << "resultToken: " << request.getResultToken() << std::endl;
  if(result_set_repository::get_instance().free_result(request.getResultToken())){
	  ZeroMessage response{};
	  return std::make_pair(Status_Success, response.getBufferData());
  }else{
	  ResponseErrorMessage errorMessage{ std::string{"Could not free result set!"} };
	  return std::make_pair(Status_Error, errorMessage.getBufferData());
  }

}
  

template<class ParserType>
void load_files(std::vector<Uri> uris, std::vector<gdf_column_cpp>& out_columns) {
		auto provider = std::make_unique<ral::io::uri_data_provider>(uris);
		std::vector<std::vector<gdf_column_cpp>> all_parts;
    while (provider->has_next()) {
      auto parser = std::make_unique<ParserType>();
      std::vector<gdf_column_cpp> columns;
		  parser->parse(provider->get_next(), columns);
      all_parts.push_back(columns);
    }
    if (all_parts.size() == 1) {
        out_columns = all_parts[0];
    } 
    else if (all_parts.size() > 1) {
      std::vector<gdf_column_cpp>& part_left = all_parts[0];
      for(size_t index_col = 0; index_col < part_left.size(); index_col++) { //iterate each one of the columns
        
        std::vector<gdf_column*> columns;
        size_t col_total_size = 0;

        for(size_t index_part = 0; index_part < all_parts.size(); index_part++) { //iterate each one of the parts 
          std::vector<gdf_column_cpp> &part = all_parts[index_part];
          auto &gdf_col = part[index_col];
          columns.push_back(gdf_col.get_gdf_column());
          col_total_size+= gdf_col.size();
        }
        gdf_column_cpp output_col;
        auto & lhs = all_parts[0][index_col];
        output_col.create_gdf_column(lhs.dtype(), col_total_size, nullptr, get_width_dtype(lhs.dtype()), lhs.name());
        gdf_error err = gdf_column_concat(output_col.get_gdf_column(), columns.data(), columns.size());
        if (err == GDF_SUCCESS) {
          out_columns.push_back(output_col);
        } else {
          std::cerr << "ERROR: gdf_column_concat\n";
        }
      }
    }
}

static result_pair executeFileSystemPlanService (uint64_t accessToken, Buffer&& requestPayloadBuffer) {
  blazingdb::message::io::FileSystemDMLRequestMessage requestPayload(requestPayloadBuffer.data());
  
  // ExecutePlan
  std::cout << "accessToken: " << accessToken << std::endl;
  std::cout << "query: " << requestPayload.statement << std::endl;
  std::cout << "tableGroup: " << requestPayload.tableGroup.name << std::endl;
 	std::cout << "tables: " << requestPayload.tableGroup.tables.size() << std::endl;
  std::cout << "tableSize: " << requestPayload.tableGroup.tables.size() << std::endl;
	std::cout << "FirstColumn File: "
			<< requestPayload.tableGroup.tables[0].files[0]
			<< std::endl;
  std::vector<std::vector<gdf_column_cpp>> input_tables;
  std::vector<std::string> table_names; 
  std::vector<std::vector<std::string>> all_column_names;
  
  for(size_t i = 0; i < requestPayload.tableGroup.tables.size(); i++) {
    auto table_info = requestPayload.tableGroup.tables[i];
    std::cout << "\n SchemaType: " << table_info.schemaType << std::endl;  
    std::vector<gdf_column_cpp> table_cpp;
    if (table_info.schemaType ==  blazingdb::protocol::io::FileSchemaType_PARQUET) {
      std::vector<Uri> uris; 
      for (auto file_path : table_info.files) {
        uris.push_back(Uri{file_path});
      }
      load_files<ral::io::parquet_parser>(uris, table_cpp);
    } else {
      std::vector<Uri> uris = { Uri{table_info.files[0]} }; //@todo, concat many files in one single table
      auto csv_params = table_info.csv;
      std::vector<gdf_dtype> types;
      for(auto val : csv_params.dtypes) {
        types.push_back( (gdf_dtype) val );
      }

      auto provider = std::make_unique<ral::io::uri_data_provider>(uris);
      auto parser = std::make_unique<ral::io::csv_parser>(csv_params.delimiter, csv_params.line_terminator, csv_params.skip_rows, csv_params.names, types);
      provider->has_next();

      size_t num_cols = csv_params.names.size();
      std::vector<bool> include_column(num_cols, true);

      std::vector<gdf_column_cpp> columns;
      parser->parse(provider->get_next(), columns, include_column);

    }
    input_tables.push_back(table_cpp); 
    table_names.push_back(table_info.name);
    all_column_names.push_back(table_info.columnNames);
  }

  // ResponseErrorMessage errorMessage{ std::string{"not yet implemented executeFileSystemPlanService"} };
  // return std::make_pair(Status_Error, errorMessage.getBufferData());

  uint64_t resultToken = 0L;
  try {
    resultToken = result_set_repository::get_instance().register_query(accessToken); 

    // void data_loader<DataProvider, FileParser>::load_data(std::vector<gdf_column_cpp> & columns, std::vector<bool> include_column){

    std::thread t = std::thread([=]{
        CodeTimer blazing_timer;
  
        blazing_frame output_frame;

        std::vector<gdf_column_cpp> columns;
        gdf_error error = evaluate_query(input_tables, table_names, all_column_names, requestPayload.statement, columns);
        
        output_frame.add_table(columns);

        double duration = blazing_timer.getDuration();
        result_set_repository::get_instance().update_token(resultToken, output_frame, duration);
    });
    t.detach();

  } catch (std::exception& error) {
     std::cout << error.what() << std::endl;
     ResponseErrorMessage errorMessage{ std::string{error.what()} };
     return std::make_pair(Status_Error, errorMessage.getBufferData());
  }

  interpreter::NodeConnectionDTO nodeInfo {
      .path = "ipc:///tmp/ral.socket",
      .type = NodeConnectionType {NodeConnectionType_IPC}
  };
  interpreter::ExecutePlanResponseMessage responsePayload{resultToken, nodeInfo};
  return std::make_pair(Status_Success, responsePayload.getBufferData());
}

static result_pair executePlanService(uint64_t accessToken, Buffer&& requestPayloadBuffer)   {
  interpreter::ExecutePlanRequestMessage requestPayload(requestPayloadBuffer.data());

  // ExecutePlan
  std::cout << "accessToken: " << accessToken << std::endl;
  std::cout << "query: " << requestPayload.getLogicalPlan() << std::endl;
  std::cout << "tableGroup: " << requestPayload.getTableGroup().name << std::endl;
 	std::cout << "tables: " << requestPayload.getTableGroup().tables.size() << std::endl;
  std::cout << "tableSize: " << requestPayload.getTableGroup().tables.size() << std::endl;
	std::cout << "FirstColumnSize: "
			<< requestPayload.getTableGroup().tables[0].columns[0].size
			<< std::endl;
  std::cout << "token: " << requestPayload.getTableGroup().tables[0].token << std::endl;
	  std::vector<void *> handles;
	std::tuple<std::vector<std::vector<gdf_column_cpp>>, std::vector<std::string>, std::vector<std::vector<std::string>>> request = libgdf::toBlazingDataframe(requestPayload.getTableGroup(),handles);

  uint64_t resultToken = 0L;
  try {
    resultToken = evaluate_query(std::get<0>(request), std::get<1>(request), std::get<2>(request),
                                        requestPayload.getLogicalPlan(), accessToken,handles);
  } catch (std::exception& error) {
     std::cout << error.what() << std::endl;
     ResponseErrorMessage errorMessage{ std::string{error.what()} };
     return std::make_pair(Status_Error, errorMessage.getBufferData());
  }
  interpreter::NodeConnectionDTO nodeInfo {
      .path = "ipc:///tmp/ral.socket",
      .type = NodeConnectionType {NodeConnectionType_IPC}
  };
  interpreter::ExecutePlanResponseMessage responsePayload{resultToken, nodeInfo};
  return std::make_pair(Status_Success, responsePayload.getBufferData());
}


static  std::map<int8_t, FunctionType> services;


//@todo execuplan with filesystem
auto  interpreterServices(const blazingdb::protocol::Buffer &requestPayloadBuffer) -> blazingdb::protocol::Buffer {
  RequestMessage request{requestPayloadBuffer.data()};
  std::cout << "header: " << (int)request.messageType() << std::endl;

  auto result = services[request.messageType()] ( request.accessToken(),  request.getPayloadBuffer() );
  ResponseMessage responseObject{result.first, result.second};
  return Buffer{responseObject.getBufferData()};
}

int main(void)
{
	std::cout << "RAL Engine starting"<< std::endl;
  auto output = new Library::Logging::CoutOutput();
  Library::Logging::ServiceLogging::getInstance().setLogOutput(output);

  blazingdb::protocol::ZeroMqServer server("ipc:///tmp/ral.socket");

  services.insert(std::make_pair(interpreter::MessageType_ExecutePlan, &executePlanService));
  services.insert(std::make_pair(interpreter::MessageType_ExecutePlanFileSystem, &executeFileSystemPlanService));

  services.insert(std::make_pair(interpreter::MessageType_CloseConnection, &closeConnectionService));
  services.insert(std::make_pair(interpreter::MessageType_GetResult, &getResultService));
  services.insert(std::make_pair(interpreter::MessageType_FreeResult, &freeResultService));
  services.insert(std::make_pair(interpreter::MessageType_RegisterFileSystem, &registerFileSystem));
  services.insert(std::make_pair(interpreter::MessageType_DeregisterFileSystem, &deregisterFileSystem));

  services.insert(std::make_pair(interpreter::MessageType_LoadCsvSchema, &loadCsvSchema));
  services.insert(std::make_pair(interpreter::MessageType_LoadParquetSchema, &loadParquetSchema));

  server.handle(&interpreterServices);

	return 0;
}
