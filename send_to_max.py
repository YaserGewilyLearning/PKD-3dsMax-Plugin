import socket
import argparse
import json
import sys

def main():
    parser = argparse.ArgumentParser(description="Send script code to 3ds Max TCP Server for execution.")
    parser.add_argument("--code", "-c", type=str, help="Code snippet to execute in 3ds Max.")
    parser.add_argument("--file", "-f", type=str, help="File path containing code to execute in 3ds Max.")
    parser.add_argument("--language", "-l", type=str, choices=["maxscript", "python"], default="maxscript",
                        help="Programming language of the code to execute (default: maxscript).")
    parser.add_argument("--port", "-p", type=int, default=8089, help="TCP port of the 3ds Max server (default: 8089).")
    
    args = parser.parse_args()
    
    # Resolve code to execute
    code_content = ""
    if args.code:
        code_content = args.code
    elif args.file:
        try:
            with open(args.file, "r", encoding="utf-8") as f:
                code_content = f.read()
        except Exception as e:
            print(f"Error: Failed to read file {args.file}: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        print("Error: Either --code (-c) or --file (-f) must be specified.", file=sys.stderr)
        parser.print_help()
        sys.exit(1)
        
    # Prepare payload
    payload = {
        "language": args.language,
        "code": code_content
    }
    
    payload_str = json.dumps(payload)
    
    # Connect and send
    try:
        client_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client_sock.connect(("127.0.0.1", args.port))
        
        # Send payload
        client_sock.sendall(payload_str.encode("utf-8"))
        # Shutdown sending side so the server knows we're done sending
        client_sock.shutdown(socket.SHUT_WR)
        
        # Read response
        response_bytes = b""
        while True:
            chunk = client_sock.recv(4096)
            if not chunk:
                break
            response_bytes += chunk
            
        client_sock.close()
        
        # Parse response
        if not response_bytes:
            print("Error: Received empty response from 3ds Max server.", file=sys.stderr)
            sys.exit(1)
            
        response_str = response_bytes.decode("utf-8")
        try:
            response = json.loads(response_str)
        except ValueError:
            print(f"Error: Server response was not valid JSON:\n{response_str}", file=sys.stderr)
            sys.exit(1)
            
        # Display response
        if response.get("status") == "success":
            print(response.get("result", ""))
            sys.exit(0)
        else:
            print(f"3ds Max Execution Error: {response.get('error')}", file=sys.stderr)
            if "traceback" in response:
                print("\nServer Traceback:", file=sys.stderr)
                print(response["traceback"], file=sys.stderr)
            sys.exit(1)
            
    except ConnectionRefusedError:
        print(f"Error: Could not connect to 3ds Max TCP server on 127.0.0.1:{args.port}.", file=sys.stderr)
        print("Please verify that 3ds Max is running and the max_server.py script has been executed.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: Communication error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
