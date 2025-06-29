#!/usr/bin/env python3
"""
Simple HTTP server for StopBrowsing redirect page
Serves on port 80 to intercept blocked website requests
"""

import http.server
import socketserver
import os
import sys
import json
import datetime
from pathlib import Path

class StopBrowsingHandler(http.server.SimpleHTTPRequestHandler):
    """Custom handler that serves our redirect page for any request"""
    
    def do_GET(self):
        """Handle GET requests by serving the redirect page"""
        # Always serve the index.html from our redirect directory
        self.path = '/index.html'
        return super().do_GET()
    
    def log_message(self, format, *args):
        """Suppress log messages"""
        pass

def main():
    if len(sys.argv) != 3:
        print("Usage: redirect_server.py <port> <redirect_dir>")
        sys.exit(1)
    
    port = int(sys.argv[1])
    redirect_dir = sys.argv[2]
    
    # Change to redirect directory
    os.chdir(redirect_dir)
    
    # Start server
    with socketserver.TCPServer(("", port), StopBrowsingHandler) as httpd:
        print(f"StopBrowsing redirect server running on port {port}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("Server stopped")

if __name__ == "__main__":
    main()