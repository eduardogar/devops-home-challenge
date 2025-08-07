import os
from flask import Flask, jsonify
import platform
import socket

app = Flask(__name__)
ENVIRONMENT_MESSAGE = os.environ.get('WELCOME_MESSAGE', 'Welcome to the DevOps Challenge!')
APP_VERSION = os.environ.get('APP_VERSION', 'v1.0.0')

@app.route('/')
def home():
    return f"<h1>{ENVIRONMENT_MESSAGE}</h1>"

@app.route('/status')
def status():
    return jsonify(status="ok", hostname=socket.gethostname(), platform=platform.system(), app_version=APP_VERSION)

@app.route('/health')
def health_check():
    return jsonify(status="ok"), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)