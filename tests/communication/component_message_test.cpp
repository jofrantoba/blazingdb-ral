#include <vector>
#include <random>
#include <algorithm>
#include "gtest/gtest.h"
#include "GDFColumn.cuh"
#include "Traits/RuntimeTraits.h"
#include "communication/network/Server.h"
#include "communication/network/Client.h"
#include "communication/factory/MessageFactory.h"


namespace {
    gdf_column_cpp createRalColumn(std::size_t size, gdf_dtype dtype) {
        std::mt19937 rng;
        auto Generator = [&rng]() {
            return (rng() % 26) + 65;
        };

        std::size_t data_size = ral::traits::get_data_size(size, dtype);
        std::vector<std::uint8_t> data;
        data.resize(data_size);

        std::size_t valid_size = ral::traits::get_valid_size(size);
        std::vector<std::uint8_t> valid;
        valid.resize(valid_size);

        std::generate_n(data.data(), data_size, Generator);
        std::generate_n(valid.data(), valid_size, Generator);

        gdf_column_cpp column;
        auto width = ral::traits::get_dtype_size(dtype);
        column.create_gdf_column(dtype, size, data.data(), valid.data(), width);

        return column;
    }

    std::vector<std::uint8_t> get_data(gdf_column* column) {
        std::vector<std::uint8_t> result;

        std::size_t data_size = ral::traits::get_data_size(column);
        result.resize(data_size);
        cudaMemcpy(result.data(), column->data, data_size, cudaMemcpyDeviceToHost);

        return result;
    }

    std::vector<std::uint8_t> get_valid(gdf_column* column) {
        std::vector<std::uint8_t> result;

        std::size_t valid_size = ral::traits::get_valid_size(column);
        result.resize(valid_size);
        cudaMemcpy(result.data(), column->valid, valid_size, cudaMemcpyDeviceToHost);

        return result;
    }
}


TEST(ComponentMessageTest, SampleToNodeMasterMessage) {
    // Make alias
    using MessageFactory = ral::communication::messages::Factory;
    namespace Messages = ral::communication::messages;

    // start server
    using ral::communication::network::Server;
    Server::start();

    // Create Data - node
    using Address = blazingdb::communication::Address;
    blazingdb::communication::Node test_node(Address::Make("1.2.3.4", 5678));

    // Create data - gdf_column_cpp
    std::vector<gdf_column_cpp> test_columns;
    test_columns.emplace_back(createRalColumn(8, GDF_INT16));
    test_columns.emplace_back(createRalColumn(16, GDF_INT64));

    {
        // Create message
        auto message = MessageFactory::createSampleToNodeMaster(test_node, test_columns);

        // Server address
        blazingdb::communication::Node server_node(Address::Make("localhost", 8000));

        // Send message to the server
        using ral::communication::network::Client;
        Client::send(server_node, message);
    }

    std::shared_ptr<Messages::SampleToNodeMasterMessage> message;
    {
        // Receive message from the client
        message = Server::getInstance().getMessage<Messages::SampleToNodeMasterMessage>();
    }

    // Tests - node in message
    {
        const auto& message_node = message->getNode();
        ASSERT_EQ(test_node, message_node);
    }

    // Tests - gdf_column_cpp in message
    {
        const auto& message_columns = message->getSamples();

        ASSERT_EQ(message_columns.size(), test_columns.size());

        for (std::size_t k = 0; k < test_columns.size(); ++k) {
            {
                auto local_data = get_data(test_columns[k].get_gdf_column());
                auto message_data = get_data(message_columns[k].get_gdf_column());
                for (std::size_t i = 0; i < local_data.size(); ++i) {
                    ASSERT_EQ(local_data[i], message_data[i]);
                }
            }
            {
                auto local_valid = get_valid(test_columns[k].get_gdf_column());
                auto message_valid = get_valid(message_columns[k].get_gdf_column());
                for (std::size_t i = 0; i < local_valid.size(); ++i) {
                    ASSERT_EQ(local_valid[i], message_valid[i]);
                }
            }
        }
    }
}