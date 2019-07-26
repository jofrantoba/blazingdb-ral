#pragma once

#include <gmock/gmock.h>
#include "blazingdb/communication/ContextToken.h"
#include "blazingdb/communication/messages/Message.h"

namespace {
using blazingdb::communication::ContextToken;
using blazingdb::communication::messages::Message;
using MessageTokenType = blazingdb::communication::messages::MessageToken::TokenType;
} // namespace

struct ServerMock {
    static ServerMock& getInstance() {
        static ServerMock mock;
        return mock;
    }

    MOCK_METHOD2(getMessage, std::shared_ptr<Message>(const ContextToken&, const MessageTokenType& ));
};
