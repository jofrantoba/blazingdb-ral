#include "communication/network/Server.h"
#include "communication/messages/ComponentMessages.h"

namespace ral {
namespace communication {
namespace network {

    void Server::start() {
        getInstance();
    }

    Server& Server::getInstance() {
        static Server server;
        return server;
    }

    Server::Server() {
        comm_server = CommServer::Make();

        setEndPoints();

        thread = std::thread([this]() {
            comm_server->Run();
        });
        std::this_thread::yield();
    }

    Server::~Server() {
        comm_server->Close();
        thread.join();
    }

    void Server::setEndPoints() {
        namespace messages = ral::communication::messages;

        comm_server->registerEndPoint(CommServer::Methods::Post, messages::SampleToNodeMasterMessage::getMessageID());
        comm_server->registerEndPoint(CommServer::Methods::Post, messages::PartitionPivotsMessage::getMessageID());
        comm_server->registerEndPoint(CommServer::Methods::Post, messages::DataScatterMessage::getMessageID());
    }

} // namespace network
} // namespace communication
} // namespace ral