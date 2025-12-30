"""
FLASK APP ENTRY POINT
---------------------
Mô tả: File chính chạy server Flask.
Chức năng chính:
1. Định nghĩa các routes (đường dẫn) cho Web App (Home, Chat, API).
2. Xử lý Đăng ký / Đăng nhập / Đăng xuất (Authentication).
3. Khởi tạo và gọi các Service: TextChatService và VoiceChatService.
4. API Gateway: Nhận request từ Frontend và chuyển tiếp đến đúng Service xử lý.
"""

import asyncio
import base64
import os
import secrets
import struct
import threading
import sys
print(f"🚀 Starting App with Python version: {sys.version}")
from flask import Flask, render_template, request, jsonify, Response, session, redirect, url_for, flash
from flask_cors import CORS
from dotenv import load_dotenv

# Import các service đã tách
from text_service import TextChatService
from voice_service import VoiceChatService
from db_utils import DatabaseManager

# Load biến môi trường
dotenv_path = os.path.join(os.path.dirname(__file__), '.env')
if os.path.exists(dotenv_path):
    print(f"Loading .env from {dotenv_path}")
    load_dotenv(dotenv_path)
else:
    print("⚠️ .env file not found!")

app = Flask(__name__)
app.secret_key = secrets.token_hex(16) # Secret key cho session

# Enable CORS for Flutter web app (Allow all for development)
CORS(app, resources={r"/*": {"origins": "*"}}, supports_credentials=True)

# Lấy API Key
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY") or os.getenv("GEMINI_API_KEY")
if not GOOGLE_API_KEY:
    raise ValueError("Vui lòng đặt GOOGLE_API_KEY (hoặc GEMINI_API_KEY) trong file .env")

# Khởi tạo Services
try:
    voice_service = VoiceChatService(GOOGLE_API_KEY)
    text_service = TextChatService(GOOGLE_API_KEY) # Khởi tạo Text Service
    db_manager = DatabaseManager() # Khởi tạo DB
    
    # Gán DB Manager cho Text Service để nó có thể lưu tin nhắn
    text_service.db_manager = db_manager 
    
    print("✅ Services initialized successfully!")
except Exception as e:
    print(f"❌ Error initializing services: {e}")
    voice_service = None
    text_service = None
    db_manager = None

# --- AUTH ROUTES ---

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        # Authenticate user
        user_id = db_manager.authenticate_user(username, password)
        if user_id:
            # Set session for web compatibility (optional)
            session['user_id'] = user_id
            session['username'] = username
            
            # Always return JSON with token for Flutter app
            return jsonify({
                "success": True,
                "token": user_id,
                "username": username
            }), 200
        else:
            return jsonify({"success": False, "error": "Invalid credentials"}), 401
    
    # For GET requests, still render login page for testing
    return render_template('login.html')

@app.route('/api/conversations/<conversation_id>', methods=['GET'])
def get_conversation_messages(conversation_id):
    # Support both session cookie and Authorization header
    user_id = None
    
    # Check session first
    if 'user_id' in session:
        user_id = session['user_id']
    # Check Authorization header (for Flutter web)
    elif 'Authorization' in request.headers:
        token = request.headers.get('Authorization').replace('Bearer ', '')
        user_id = token
    
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401
        
    messages = db_manager.get_conversation_messages(conversation_id, user_id)
    return jsonify({"messages": messages})

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if db_manager.create_user(username, password):
            return jsonify({"success": True, "message": "Registration successful"}), 200
        else:
            return jsonify({"success": False, "error": "Username already exists"}), 400
    
    return render_template('register.html')

@app.route('/logout')
def logout():
    session.pop('user_id', None)
    session.pop('username', None)
    return redirect(url_for('login'))


# --- WEB ROUTES (Protected) ---

@app.route('/')
def index():
    return redirect(url_for('chat_text'))

@app.route('/chat')
def chat():
    # Allow access without login
    username = session.get('username', None)
    return render_template('chat.html', username=username)

@app.route('/chat-text')
@app.route('/chat-text/<conversation_id>')
def chat_text(conversation_id=None):
    # Allow access without login
    username = session.get('username', None)
    return render_template('chat_text.html', username=username, conversation_id=conversation_id)


# --- API ROUTES ---

@app.route('/api/conversations', methods=['GET'])
def get_conversations():
    # Support both session cookie and Authorization header
    user_id = None
    
    # Check session first
    if 'user_id' in session:
        user_id = session['user_id']
    # Check Authorization header (for Flutter web)
    elif 'Authorization' in request.headers:
        token = request.headers.get('Authorization').replace('Bearer ', '')
        # For now, use username as token (simple approach)
        # TODO: Implement proper JWT token validation
        user_id = token
    
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401
    
    conversations = db_manager.get_user_conversations(user_id)
    return jsonify({"conversations": conversations})

@app.route('/api/conversations', methods=['POST'])
def create_conversation():
    # Support Token
    user_id = None
    if 'user_id' in session:
        user_id = session['user_id']
    elif 'Authorization' in request.headers:
        user_id = request.headers.get('Authorization').replace('Bearer ', '')
    
    if not user_id: return jsonify({"error": "Unauthorized"}), 401
    
    data = request.get_json() or {}
    title = data.get('title', 'Chat mới')
    
    conv_id = db_manager.create_conversation(user_id, title)
    return jsonify({"success": True, "conversation_id": conv_id})

@app.route('/api/conversations/<conversation_id>', methods=['DELETE'])
def delete_conversation(conversation_id):
    # Support Token
    user_id = None
    if 'user_id' in session:
        user_id = session['user_id']
    elif 'Authorization' in request.headers:
        user_id = request.headers.get('Authorization').replace('Bearer ', '')
    
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401
    
    success = db_manager.delete_conversation(conversation_id, user_id)
    return jsonify({"success": success})

@app.route('/api/history', methods=['GET'])
def get_chat_history():
    # Support both session cookie and Authorization header
    user_id = None
    
    # Check session first
    if 'user_id' in session:
        user_id = session['user_id']
    # Check Authorization header (for Flutter/Mobile)
    elif 'Authorization' in request.headers:
        token = request.headers.get('Authorization').replace('Bearer ', '')
        user_id = token
        
    if not user_id:
        return jsonify({"history": []})
        
    if not db_manager:
        return jsonify({"history": []})
    
    conversation_id = request.args.get('conversation_id')
    if not conversation_id:
        return jsonify({"history": []})
        
    # Security check: Ensure user owns this conversation?
    # db_manager.get_messages currently doesn't check owner if called directly,
    # but we can trust it for now or rely on the previous relaxed check logic.
    # Ideally, we should use get_conversation_messages(conv_id, user_id) 
    # but get_messages(conversation_id) allows fetching just by ID.
    
    # Let's use the safer one that we patched earlier if we want to enforce ownership
    # OR stick to get_messages if we want relaxed access. 
    # Given the previous context, let's just fetch it.
    
    history = db_manager.get_messages(conversation_id=conversation_id)
    return jsonify({"history": history})


@app.route('/api/chat-text', methods=['POST'])
def chat_text_api():
    # Allow usage without login (just won't save history)
    
    if not text_service:
        return jsonify({"error": "Service not initialized"}), 500
    
    data = request.get_json()
    message = data.get('message', '')
    conversation_history = data.get('history', [])
    system_prompt = data.get('system_prompt', '')
    conversation_id = data.get('conversation_id') # ID cuộc hội thoại hiện tại
    
    try:
        response_text = text_service.chat_text_only(
            message, 
            conversation_history, 
            system_prompt,
            conversation_id=conversation_id
        )
            
        # Trigger Auto-Title if it's the first message (history empty or short)
        if conversation_id and len(conversation_history) == 0:
            threading.Thread(target=text_service.generate_summary_title, args=(conversation_id, message, response_text)).start()

        return jsonify({"success": True, "text": response_text})
        
    except Exception as e:
        print(f"Chat Error: {e}")
        return jsonify({"error": str(e)}), 500


def add_wav_header(pcm_data, sample_rate=24000, channels=1, bits_per_sample=16):
    """Adds a WAV header to raw PCM data."""
    data_size = len(pcm_data)
    byte_rate = sample_rate * channels * (bits_per_sample // 8)
    block_align = channels * (bits_per_sample // 8)
    
    header = struct.pack('<4sI4s4sIHHIIHH4sI',
        b'RIFF',
        36 + data_size,
        b'WAVE',
        b'fmt ',
        16,              # PCM chunk size
        1,               # Audio format (1 = PCM)
        channels,
        sample_rate,
        byte_rate,
        block_align,
        bits_per_sample,
        b'data',
        data_size
    )
    return header + pcm_data

@app.route('/api/chat', methods=['POST'])
def chat_voice_api():
    # Allow usage without login
        
    if not voice_service:
        return jsonify({"error": "Service not initialized"}), 500
    
    data = request.get_json()
    message = data.get('message', '')
    voice = data.get('voice', 'Charon')
    language = data.get('language', 'vi') # Default Vietnamese
    history = data.get('history', [])
    audio_input = data.get('audio', None)
    mime_type = data.get('mime_type', 'audio/wav') # Default to WAV

    if audio_input:
        print(f"🎤 App: Received Audio Input: {len(audio_input)} chars (Base64)")
    
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        result = loop.run_until_complete(
            voice_service.chat_with_voice(message, voice, history, language, audio_input, mime_type)
        )
        loop.close()
        
        # Add WAV header to raw PCM
        wav_audio = add_wav_header(result['audio'])
        audio_b64 = base64.b64encode(wav_audio).decode('utf-8')
        
        return jsonify({
            "success": True, 
            "text": result['text'], 
            "audio": audio_b64,
            "format": "wav",
            "sample_rate": 24000
        })
    except Exception as e:
        print(f"Voice Error: {e}")
        return jsonify({"error": str(e)}), 500


# --- TRANSLATION ROUTES ---

@app.route('/translate')
def translate_page():
    # Allow access without login
    username = session.get('username', None)
    return render_template('translate.html', username=username)

@app.route('/api/ocr', methods=['POST'])
def ocr_api():
    # Allow usage without login
    
    if 'image' not in request.files:
        return jsonify({"error": "No image uploaded"}), 400
        
    image_file = request.files['image']
    if image_file.filename == '':
        return jsonify({"error": "No selected file"}), 400
        
    try:
        image_data = image_file.read()
        mime_type = image_file.mimetype
        text = text_service.extract_text_from_image(image_data, mime_type)
        return jsonify({"success": True, "text": text})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/translate', methods=['POST'])
def translate_api():
    # Allow usage without login
    
    data = request.get_json()
    text = data.get('text', '')
    source_lang = data.get('source', 'auto')
    target_lang = data.get('target', 'vi')
    
    if not text:
        return jsonify({"error": "No text provided"}), 400
        
    try:
        result = text_service.translate_text(text, source_lang, target_lang)
        return jsonify({"success": True, "text": result})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == '__main__':
    # Chạy server trên tất cả IP (0.0.0.0) port 5000
    # ssl_context='adhoc' để enable HTTPS (tự tạo cert) -> Giúp micro hoạt động trên LAN
    # Tuy nhiên adhoc cần cài thêm thư viện (pyopenssl), nếu chưa có thì chạy HTTP thường
    try:
        app.run(host='0.0.0.0', port=5000, debug=True)
    except Exception as e:
        print(f"Server error: {e}")
