import socket
import threading
import queue
import json
import traceback
import sys

# Try to import PySide6 (3ds Max 2025+) or PySide2 (3ds Max 2021-2024)
try:
    from PySide6 import QtCore
except ImportError:
    try:
        from PySide2 import QtCore
    except ImportError:
        QtCore = None

import pymxs
rt = pymxs.runtime

class MaxServer:
    def __init__(self, host='127.0.0.1', port=8089):
        self.host = host
        self.port = port
        self.server_socket = None
        self.is_running = False
        self.cmd_queue = queue.Queue()
        self.timer = None
        self.thread = None

    def start(self):
        if self.is_running:
            print("3ds Max TCP Server: Already running.")
            return
        
        self.is_running = True
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            self.server_socket.bind((self.host, self.port))
            self.server_socket.listen(5)
            print(f"3ds Max TCP Server: Started and listening on {self.host}:{self.port}")
        except Exception as e:
            print(f"3ds Max TCP Server: Failed to bind to {self.host}:{self.port} - {e}")
            self.is_running = False
            return

        # QTimer for GUI-safe execution on the main thread
        if QtCore:
            self.timer = QtCore.QTimer()
            self.timer.timeout.connect(self.process_queue)
            self.timer.start(100)  # Check every 100 milliseconds
            print("3ds Max TCP Server: QTimer initialized for GUI-thread execution safety.")
        else:
            print("3ds Max TCP Server WARNING: PySide (Qt) not found! Executions will run on background thread (UNSAFE in 3ds Max).")

        # Background thread to accept TCP client connections
        self.thread = threading.Thread(target=self.listen_loop, daemon=True)
        self.thread.start()

    def listen_loop(self):
        while self.is_running:
            try:
                client_sock, addr = self.server_socket.accept()
                
                # Read incoming data until client shuts down write half or disconnects
                data = b""
                while self.is_running:
                    chunk = client_sock.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                
                request_str = data.decode('utf-8')
                
                if QtCore:
                    # Put request in queue to be executed on main thread by QTimer
                    self.cmd_queue.put((client_sock, request_str))
                else:
                    # Execute immediately if QTimer is not available (unsafe)
                    self.execute_immediately(client_sock, request_str)
                    
            except Exception as e:
                if self.is_running:
                    print(f"3ds Max TCP Server: Connection error in listener: {e}")

    def execute_immediately(self, client_sock, request_str):
        # Fallback thread-unsafe execution
        response = self.execute_code(request_str)
        try:
            client_sock.sendall(json.dumps(response).encode('utf-8'))
            client_sock.close()
        except Exception as e:
            print(f"3ds Max TCP Server: Failed to send response: {e}")

    def process_queue(self):
        while not self.cmd_queue.empty():
            try:
                client_sock, request_str = self.cmd_queue.get_nowait()
            except queue.Empty:
                break
                
            response = self.execute_code(request_str)
            try:
                client_sock.sendall(json.dumps(response).encode('utf-8'))
                client_sock.close()
            except Exception as e:
                print(f"3ds Max TCP Server: Failed to send response: {e}")

    def execute_code(self, request_str):
        language = "maxscript"
        code = request_str
        
        # Try parsing as JSON first
        try:
            payload = json.loads(request_str)
            if isinstance(payload, dict) and "code" in payload:
                code = payload["code"]
                language = payload.get("language", "maxscript").lower()
        except ValueError:
            # Plain text fallback, detect #python prefix
            if request_str.strip().startswith("#python"):
                language = "python"
                code = request_str.replace("#python", "", 1)

        result_val = None
        try:
            if language == "python":
                # Execute Python code in 3ds Max context
                # To capture stdout, we can optionally redirect it, but simple exec is standard.
                local_vars = {}
                exec(code, globals(), local_vars)
                result_val = local_vars.get("result", "Python code executed successfully (no 'result' variable returned).")
            else:
                # Execute MaxScript code
                # pymxs.runtime.execute returns the evaluation of the last expression
                result_val = rt.execute(code)
                
            return {
                "status": "success",
                "result": str(result_val)
            }
        except Exception as e:
            tb_str = traceback.format_exc()
            return {
                "status": "error",
                "error": str(e),
                "traceback": tb_str
            }

    def stop(self):
        self.is_running = False
        if self.server_socket:
            try:
                # Connect to self to unblock accept()
                temp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                temp_sock.connect((self.host, self.port))
                temp_sock.close()
            except:
                pass
            self.server_socket.close()
            
        if self.timer:
            self.timer.stop()
        print("3ds Max TCP Server: Stopped.")

# Clean up previous instance if running (hot reload support)
if 'max_server_instance' in globals():
    try:
        max_server_instance.stop()
        print("3ds Max TCP Server: Stopped existing server instance.")
    except Exception as e:
        print(f"3ds Max TCP Server: Error stopping existing instance: {e}")

# Instantiate and start
max_server_instance = MaxServer()
max_server_instance.start()
