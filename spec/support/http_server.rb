# frozen_string_literal: true

require "socket"

# Real loopback sockets exercise Net::HTTP; no API credentials or external traffic.
module HTTPServer
  def with_http_server(handler)
    server = TCPServer.new("127.0.0.1", 0)
    workers = []
    listener = Thread.new do
      loop do
        socket = server.accept
        workers << Thread.new(socket) do |connection|
          request_line = connection.gets
          headers = {}
          while (line = connection.gets) && line != "\r\n"
            name, value = line.split(":", 2)
            headers[name.downcase] = value.strip
          end
          body = connection.read(headers.fetch("content-length", "0").to_i)
          handler.call(connection, request_line, headers, body)
        rescue IOError, SystemCallError
          # The client may close a canceled/timed-out connection.
        ensure
          connection.close
        end
      end
    end
    yield "http://127.0.0.1:#{server.addr[1]}"
  ensure
    listener&.kill&.join
    server&.close
    workers&.each { |worker| worker.kill.join }
  end

  def send_json(socket, body, status: 200, headers: {})
    payload = JSON.generate(body)
    fields = headers.merge("Content-Type" => "application/json", "Content-Length" => payload.bytesize,
                           "Connection" => "close")
    socket.write("HTTP/1.1 #{status} Test\r\n#{fields.map { |k, v| "#{k}: #{v}\r\n" }.join}\r\n#{payload}")
  end
end
