import socket
import select
import threading
import sys
import re

def resolve_dns_custom(domain, dns_ip='8.8.8.8'):
    try:
        # Check if already an IP
        if re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', domain):
            return domain
        
        # Build query packet
        packet = bytearray()
        packet.extend(b'\x12\x34') # ID
        packet.extend(b'\x01\x00') # Flags
        packet.extend(b'\x00\x01') # Questions: 1
        packet.extend(b'\x00\x00\x00\x00\x00\x00') # Answers, Authority, Additional: 0
        for part in domain.split('.'):
            packet.append(len(part))
            packet.extend(part.encode('utf-8'))
        packet.append(0)
        packet.extend(b'\x00\x01') # Type: A
        packet.extend(b'\x00\x01') # Class: IN
        
        # UDP Query
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(2.0)
        sock.sendto(packet, (dns_ip, 53))
        data, _ = sock.recvfrom(1024)
        
        # Parse A record
        query_len = 12 + sum(len(p) + 1 for p in domain.split('.')) + 1 + 4
        idx = query_len
        while idx < len(data):
            if data[idx] & 0xc0 == 0xc0:
                idx += 2
            else:
                while data[idx] != 0:
                    idx += data[idx] + 1
                idx += 1
            rtype = int.from_bytes(data[idx:idx+2], 'big')
            rclass = int.from_bytes(data[idx+2:idx+4], 'big')
            idx += 8
            rdlen = int.from_bytes(data[idx:idx+2], 'big')
            idx += 2
            if rtype == 1 and rclass == 1 and rdlen == 4:
                return socket.inet_ntoa(data[idx:idx+4])
            idx += rdlen
    except Exception:
        pass
    return None

class HTTPProxy:
    def __init__(self, host='127.0.0.1', port=8888):
        self.host = host
        self.port = port
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind((self.host, self.port))
        self.server.listen(100)

    def handle_client(self, client_sock):
        try:
            request = client_sock.recv(4096)
            if not request:
                client_sock.close()
                return
            
            # Parse the first line to get host and port
            first_line = request.split(b'\n')[0]
            parts = first_line.split(b' ')
            if len(parts) < 2:
                client_sock.close()
                return
            url = parts[1]
            
            if first_line.startswith(b'CONNECT'):
                # HTTPS Tunneling (CONNECT method)
                if b':' in url:
                    hostname, port = url.split(b':')
                    port = int(port)
                else:
                    hostname = url
                    port = 443
                
                hostname_str = hostname.decode('utf-8') if isinstance(hostname, bytes) else str(hostname)
                connect_target = resolve_dns_custom(hostname_str)
                if not connect_target:
                    connect_target = hostname_str
                
                # Connect to the destination server
                remote_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                remote_sock.connect((connect_target, port))
                
                # Respond to client that connection is established
                client_sock.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
                
                # Forward packets in both directions
                self.tunnel(client_sock, remote_sock)
            else:
                # HTTP Proxying
                if b'://' in url:
                    url = url.split(b'://')[1]
                path_parts = url.split(b'/')
                host_port = path_parts[0]
                if b':' in host_port:
                    hostname, port = host_port.split(b':')
                    port = int(port)
                else:
                    hostname = host_port
                    port = 80
                
                hostname_str = hostname.decode('utf-8') if isinstance(hostname, bytes) else str(hostname)
                connect_target = resolve_dns_custom(hostname_str)
                if not connect_target:
                    connect_target = hostname_str
                
                remote_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                remote_sock.connect((connect_target, port))
                remote_sock.sendall(request)
                
                self.tunnel(client_sock, remote_sock)
        except Exception:
            pass
        finally:
            try:
                client_sock.close()
            except Exception:
                pass

    def tunnel(self, client_sock, remote_sock):
        inputs = [client_sock, remote_sock]
        while True:
            readable, _, _ = select.select(inputs, [], [], 60)
            if not readable:
                break
            for sock in readable:
                try:
                    data = sock.recv(4096)
                    if not data:
                        return
                    if sock is client_sock:
                        remote_sock.sendall(data)
                    else:
                        client_sock.sendall(data)
                except Exception:
                    return

    def start(self):
        print(f"Starting HTTP/HTTPS proxy on {self.host}:{self.port}...", flush=True)
        while True:
            try:
                client_sock, _ = self.server.accept()
                threading.Thread(target=self.handle_client, args=(client_sock,), daemon=True).start()
            except Exception as e:
                print(f"Error accepting connection: {e}", file=sys.stderr, flush=True)

if __name__ == '__main__':
    port = 8888
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    proxy = HTTPProxy(port=port)
    proxy.start()
