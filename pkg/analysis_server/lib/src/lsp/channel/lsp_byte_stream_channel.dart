// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analysis_server/lsp_protocol/protocol_generated.dart';
import 'package:analysis_server/lsp_protocol/protocol_special.dart';
import 'package:analysis_server/src/analysis_server.dart';
import 'package:analysis_server/src/lsp/channel/lsp_channel.dart';
import 'package:analysis_server/src/lsp/lsp_packet_transformer.dart';

/**
 * Instances of the class [LspByteStreamServerChannel] implement an
 * [LspServerCommunicationChannel] that uses a stream and a sink (typically,
 * standard input and standard output) to communicate with clients.
 */
class LspByteStreamServerChannel implements LspServerCommunicationChannel {
  final Stream _input;

  final IOSink _output;

  /**
   * Completer that will be signalled when the input stream is closed.
   */
  final Completer _closed = new Completer();

  /**
   * True if [close] has been called.
   */
  bool _closeRequested = false;

  LspByteStreamServerChannel(this._input, this._output);

  /**
   * Future that will be completed when the input stream is closed.
   */
  Future get closed {
    return _closed.future;
  }

  @override
  void close() {
    if (!_closeRequested) {
      _closeRequested = true;
      assert(!_closed.isCompleted);
      _closed.complete();
    }
  }

  @override
  void listen(void onMessage(IncomingMessage message),
      {Function onError, void onDone()}) {
    _input.transform(new LspPacketTransformer()).listen(
      (String data) => _readMessage(data, onMessage),
      onError: onError,
      onDone: () {
        close();
        onDone();
      },
    );
  }

  @override
  void sendNotification(NotificationMessage notification) =>
      _sendLsp(notification.toJson());

  @override
  void sendResponse(ResponseMessage response) => _sendLsp(response.toJson());

  /// Sends a message prefixed with the required LSP headers.
  void _sendLsp(Map<String, Object> json) {
    // Don't send any further responses after the communication channel is
    // closed.
    if (_closeRequested) {
      return;
    }
    ServerPerformanceStatistics.serverChannel.makeCurrentWhile(() {
      final jsonEncodedBody = jsonEncode(json);
      final utf8EncodedBody = utf8.encode(jsonEncodedBody);
      final header = 'Content-Length: ${utf8EncodedBody.length}\r\n'
          'Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n';
      final asciiEncodedHeader = ascii.encode(header);

      // Header is always ascii, body is always utf8!
      _write(asciiEncodedHeader);
      _write(utf8EncodedBody);

      // TODO(dantup): This...
      //_instrumentationService.logResponse(jsonEncoded);
    });
  }

  /**
   * Send [bytes] to [_output].
   */
  void _write(List<int> bytes) {
    runZoned(
      () => _output.add(bytes),
      onError: (e) => close(),
    );
  }

  /**
   * Read a request from the given [data] and use the given function to handle
   * the message.
   */
  void _readMessage(String data, void onMessage(IncomingMessage request)) {
    // Ignore any further requests after the communication channel is closed.
    if (_closed.isCompleted) {
      return;
    }
    ServerPerformanceStatistics.serverChannel.makeCurrentWhile(() {
      // TODO(dantup): This...
      //_instrumentationService.logRequest(data);
      final Map<String, Object> json = jsonDecode(data);
      if (RequestMessage.canParse(json)) {
        onMessage(RequestMessage.fromJson(json));
      } else if (NotificationMessage.canParse(json)) {
        onMessage(NotificationMessage.fromJson(json));
      } else {
        // TODO(dantup): Report error
      }
    });
  }
}