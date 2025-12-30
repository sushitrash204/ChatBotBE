"""
VOICE CHAT & TTS SERVICE MODULE
-------------------------------
Mô tả: File này xử lý các chức năng liên quan đến Âm thanh (Audio).
Chức năng chính:
1. Kết nối với Google Gemini Live API qua WebSocket.
2. Text-to-Speech (TTS): Chuyển văn bản thành giọng nói.
3. Chat Voice: Hội thoại 2 chiều (User nhắn text -> AI trả lời bằng Audio + Text).
4. Tích hợp cơ chế "Jailbreak" cho Voice Chat.
"""

import asyncio
import base64
import json
import websockets
from db_utils import DatabaseManager

class VoiceChatService:
    def __init__(self, api_key: str):
        self.api_key = api_key
        # Model Gemini Flash hỗ trợ Audio native
        self.model = "gemini-2.5-flash-native-audio-latest"
        # WebSocket URL
        self.ws_url = f"wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key={api_key}"
        
        # Kết nối DB (dự phòng, hiện tại Voice chưa lưu history nhưng có sẵn để dùng)
        self.db_manager = DatabaseManager()

    async def text_to_speech(self, text: str, voice: str = "Puck") -> bytes:
        """
        Chuyển đổi Text thành Audio (TTS).
        Sử dụng WebSocket để gửi text và nhận về các chunk audio PCM.
        """
        audio_chunks = []
        try:
            async with websockets.connect(self.ws_url) as ws:
                # 1. Gửi tin nhắn Setup (cấu hình voice)
                setup_message = {
                    "setup": {
                        "model": f"models/{self.model}",
                        "systemInstruction": {
                            "parts": [{"text": "You are a helpful reading assistant. Read the provided text clearly and naturally."}]
                        },
                        "generationConfig": {
                            "responseModalities": ["AUDIO"],
                            "speechConfig": {
                                "voiceConfig": {
                                    "prebuiltVoiceConfig": {
                                        "voiceName": voice
                                    }
                                }
                            }
                        }
                    }
                }
                
                await ws.send(json.dumps(setup_message))
                setup_resp = await ws.recv() # Đợi xác nhận setup
                print(f"✅ TTS Setup Response: {setup_resp}")
                
                # 2. Gửi yêu cầu đọc văn bản
                prompt_message = {
                    "clientContent": {
                        "turns": [{
                            "role": "user",
                            "parts": [{"text": f"Please read this text aloud: {text}"}]
                        }],
                        "turnComplete": True
                    }
                }
                
                await ws.send(json.dumps(prompt_message))
                
                # 3. Nhận phản hồi
                while True:
                    try:
                        response = await asyncio.wait_for(ws.recv(), timeout=10.0)
                        data = json.loads(response)
                        
                        if "serverContent" in data:
                            server_content = data["serverContent"]
                            if "modelTurn" in server_content:
                                parts = server_content["modelTurn"].get("parts", [])
                                for part in parts:
                                    if "inlineData" in part: # Audio data
                                        audio_b64 = part["inlineData"]["data"]
                                        audio_chunks.append(base64.b64decode(audio_b64))
                            if server_content.get("turnComplete", False):
                                break
                    except asyncio.TimeoutError:
                        break
                    except Exception:
                        break
        except Exception as e:
            print(f"TTS WebSocket error: {e}")
            raise
        
        return b''.join(audio_chunks)
    async def chat_with_voice(self, message: str, voice: str = "Puck", conversation_history: list = None, language: str = "vi", audio_input: str = None, mime_type: str = "audio/wav") -> dict:
        """
        Chat Voice 2 chiều.
        Input: Tin nhắn text của User.
        Output: Audio giọng nói của AI + Text phản hồi.
        """
        audio_chunks = []
        response_text = ""
        
        try:
            async with websockets.connect(self.ws_url) as ws:
                # 1. Setup session
                # Gemini Multimodal Live API (WebSocket) 
                # Dùng camelCase cho protocol WebSocket v1beta
                setup_message = {
                    "setup": {
                        "model": f"models/{self.model}",
                        "systemInstruction": { 
                            "parts": [{"text": f"You are a helpful voice assistant. Listen to the user's audio or read their text, transcribe/process it, and respond naturally in {language}. DO NOT output your internal thoughts, reasoning, or headers. ONLY output the final spoken response."}]
                        },
                        "generationConfig": { 
                            "responseModalities": ["AUDIO"], 
                            "speechConfig": {
                                "voiceConfig": {
                                    "prebuiltVoiceConfig": {"voiceName": voice}
                                }
                            }
                        }
                    }
                }
                
                await ws.send(json.dumps(setup_message))
                try:
                    setup_confirm_raw = await asyncio.wait_for(ws.recv(), timeout=10.0)
                    setup_confirm = json.loads(setup_confirm_raw)
                    print(f"✅ Voice Chat Setup Response: {setup_confirm_raw}", flush=True)
                    
                    if "setupComplete" not in setup_confirm:
                        print(f"🛑 Gemini Setup Failed! Response: {setup_confirm_raw}", flush=True)
                except asyncio.TimeoutError:
                    print("🛑 Setup Timeout: Gemini did not respond to setup message.", flush=True)
                    raise Exception("Gemini Setup Timeout")
                
                # 2. Tin nhắn hội thoại
                turns = []
                
                # 3. Thêm tin nhắn hiện tại (Hỗ trợ cả MESSAGE TEXT và AUDIO)
                current_parts = []
                
                if message:
                    print(f"💬 Text input detected: {message}", flush=True)
                    current_parts.append({"text": message})
                
                if audio_input:
                    # Log định dạng gốc để debug
                    print(f"DEBUG: Original Mime: {mime_type}", flush=True)
                    audio_bytes_raw = base64.b64decode(audio_input)
                    audio_bytes_len = len(audio_bytes_raw)
                    print(f"📥 Input Audio Size: {audio_bytes_len} bytes", flush=True)
                    
                    final_mime = "audio/webm;codecs=opus" if "webm" in mime_type.lower() else "audio/l16;rate=24000"
                    processed_audio = audio_input
                    
                    if "wav" in final_mime.lower() or "l16" in final_mime.lower():
                        if audio_bytes_raw.startswith(b'RIFF'):
                            print("✂️ [WAV] Detected RIFF header. Stripping 44 bytes...", flush=True)
                            audio_bytes_stripped = audio_bytes_raw[44:]
                            processed_audio = base64.b64encode(audio_bytes_stripped).decode('utf-8')

                    print(f"🎤 Sending Audio to Gemini with MIME: {final_mime}", flush=True)
                    current_parts.append({
                        "inlineData": { 
                            "mimeType": final_mime,
                            "data": processed_audio
                        }
                    })
                
                if not current_parts:
                    raise Exception("No input provided (neither text nor audio)")

                turns.append({
                    "role": "user",
                    "parts": current_parts
                })

                # --- FINAL TURNS ---
                final_turns = turns
                
                # 4. Gửi toàn bộ nội dung
                prompt_input = {
                    "clientContent": {
                        "turns": final_turns,
                        "turnComplete": True
                    }
                }
                
                print(f"DEBUG: Prompt Request: {json.dumps(prompt_input)[:200]}...")
                await ws.send(json.dumps(prompt_input))
                
                # 5. Nhận phản hồi (Audio + Text)
                print("⏳ Waiting for Gemini response...")
                while True:
                    try:
                        response = await asyncio.wait_for(ws.recv(), timeout=15.0)
                        data = json.loads(response)
                        
                        # Debug: Log response structure
                        # print(f"📡 WebSocket Response: {data}") # TOO NOISY
                        
                        if "serverContent" in data:
                            server_content = data["serverContent"]
                            if "modelTurn" in server_content:
                                parts = server_content["modelTurn"].get("parts", [])
                                print(f"📦 Received {len(parts)} parts from Gemini")
                                for part in parts:
                                    if "text" in part: # Nhận Text
                                        response_text += part["text"]
                                        print(f"📝 Text part: {part['text'][:100]}...")
                                    if "inlineData" in part: # Nhận Audio chunks
                                        audio_b64 = part["inlineData"]["data"]
                                        audio_chunks.append(base64.b64decode(audio_b64))
                                        print(f"🔊 Audio chunk: {len(audio_b64)} bytes (base64)")
                        if server_content.get("turnComplete", False):
                                print("DEBUG: Turn Complete received")
                                break
                        else:
                            print(f"⚠️ Unexpected response keys: {data.keys()}")
                            if "error" in data:
                                print(f"🛑 Gemini Error Data: {json.dumps(data['error'])}")
                    except asyncio.TimeoutError:
                        print("⏱️ WebSocket timeout")
                        break
                    except Exception as e:
                        print(f"❌ WebSocket receive error: {e}")
                        break
                        
        except Exception as e:
            import traceback
            print(f"Voice Chat WebSocket error: {e}")
            print(traceback.format_exc())
            raise
            
        # 6. Chuẩn bị kết quả
        # Thêm 0.3s im lặng (\x00) vào đầu để tránh Chrome bị mất tiếng lúc bắt đầu (Hardware lag)
        # 24000 samples/s * 0.3s * 2 bytes = 14400 bytes
        silence_padding = b'\x00' * int(24000 * 0.3 * 2)
        raw_audio = silence_padding + b''.join(audio_chunks)
        total_audio_len = len(raw_audio)
        
        # Estimate duration: Gemini output is usually 24kHz, 16-bit PCM mono
        duration_sec = total_audio_len / (24000 * 2) 
        print(f"🎤 AI Response: {len(response_text)} chars, {total_audio_len} bytes (~{duration_sec:.2f}s, included 0.3s padding)")
        
        # Filter out thoughts/headers (lines starting with ** or similar)
        import re
        clean_text = re.sub(r'\*\*.*?\*\*', '', response_text).strip() # Remove **Header**
        # Remove lines that look like reasoning if mixed (simple heuristic)
        
        return {
            "text": clean_text if clean_text else response_text.strip(),
            "audio": raw_audio
        }
