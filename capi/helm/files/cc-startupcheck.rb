require 'socket'

UNIXSocket.open('/var/run/cloud_controller.sock') do |socket|
  socket.write("GET /healthz HTTP/1.0\r\n\r\n")
  abort unless socket.gets&.split&.at(1) == '200'
end
