#include "CommunicationData.h"

namespace ral {
namespace communication {
using namespace blazingdb::communication;

CommunicationData::CommunicationData() : orchestratorPort{0} {}

CommunicationData& CommunicationData::getInstance() {
  static CommunicationData communicationData;
  return communicationData;
}

void CommunicationData::initialize(int unixSocketId,
                                   const std::string& orchIp,
                                   int16_t orchCommunicationPort,
                                   const std::string& selfRalIp,
                                   int16_t selfRalCommunicationPort,
                                   int16_t selfRalProtocolPort) {
  orchestratorIp = orchIp;
  orchestratorPort = orchCommunicationPort;
  selfNode = Node::make(unixSocketId, selfRalIp, selfRalCommunicationPort, selfRalProtocolPort);
}

const Node& CommunicationData::getSelfNode() { return *selfNode; }

std::string CommunicationData::getOrchestratorIp() { return orchestratorIp; }

int16_t CommunicationData::getOrchestratorPort() { return orchestratorPort; }

}  // namespace communication
}  // namespace ral