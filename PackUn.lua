#!/usr/bin/env lua
-- lua websocket equivalent to test-server.c from libwebsockets.
-- using copas as server framework
package.path = './websocket/?.lua;../src/?/?.lua;'..package.path
module(... or '', package.seeall);

require('Comm');
require('Z');
json = require "json";
local copas = require'copas'
local socket = require'socket'
local websocket = require'websocket'
local inc_clients = {}
local data;
print('Open browser:')
print('file://'..io.popen('pwd'):read()..'/index.html')

Comm.init('192.168.1.255','83790');

function recv_msgs()
  while (Comm.size() > 0) do
    packet = Comm.receive()

    rpacket = deserialize(packet);
    if(rpacket ~= "") then
      packet_c = rpacket.comp
      packet_uc = Z.uncompress(packet_c, #packet_c)
      dData = deserialize(packet_uc);
      data = json.encode(dData);
      print(data);
    end
  end
end

function deserialize(s)
  --local x = assert(loadstring("return "..s))();
  if not s then
    return '';
  end
  -- protected loadstring call
  ok, ret = pcall(loadstring('return '..s));
  --local x = loadstring("return "..s)();
  if not ok then 
    --print(string.format("Warning: Could not deserialize message:\n%s",s));
    return '';
  else
    return ret;
  end
end

local server = websocket.server.copas.listen
{
  protocols = {
    ['lws-mirror-protocol'] = function(ws)
      while true do
        local msg,opcode = ws:receive()
        if not msg then
          ws:close()
          print('ws closed lws-mirror-protocol')
          return
        end
        if opcode == websocket.TEXT then
          ws:broadcast(msg)
          print('ws broadcast lws-mirror-protocol', msg)
        end
      end
    end,
    ['dumb-increment-protocol'] = function(ws)
      inc_clients[ws] = 0
      while true do
        local message,opcode = ws:receive()
        if not message then
          ws:close()
          print('ws closed dumb-increment-protocol')
          inc_clients[ws] = nil
          return
        end
        if opcode == websocket.TEXT then
          if message:match('reset') then
            inc_clients[ws] = 0
          end
        end
      end
    end
  },
  port = 5056
  
}

-- this fairly complex mechanism is required due to the
-- lack of copas timers...
-- sends periodically the 'dumb-increment-protocol' count
-- to the respective client.
copas.addthread(
  function()
    local last = socket.gettime()
    while true do
      copas.step(0)
      local now = socket.gettime()
      if (now - last) >= 0.1 then
        recv_msgs();
        last = now
        if(data ~= "") then
          for ws,number in pairs(inc_clients) do
            ws:send(data)
            data = "";
            inc_clients[ws] = number + 1
          end
        end
      end
    end
  end)

copas.loop()
