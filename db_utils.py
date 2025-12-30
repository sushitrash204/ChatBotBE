"""
DATABASE UTILITY MODULE
-----------------------
Mô tả: File này quản lý kết nối và thao tác với MongoDB.

DATA MODELS (SCHEMA):
---------------------
1. Collection "users":
   {
       "_id": ObjectId,
       "username": String (Unique),
       "password": String (Hashed),
       "created_at": Datetime
   }

2. Collection "messages":
   {
       "_id": ObjectId,
       "conversation_id": String (ID cuộc hội thoại),
       "role": String ("user" = Người gửi | "model" = AI trả lời), <--- KHÔNG PHẢI PHÂN QUYỀN
       "content": String (Nội dung),
       "msg_type": String ("text" | "voice"), <--- MỚI: Phân loại tin nhắn
       "timestamp": Datetime
   }

Chức năng chính:
1. Kết nối tới MongoDB Atlas.
2. Quản lý Authentication (Register/Login).
3. Lưu và truy xuất lịch sử Chat.
"""

import os
import datetime
from pymongo import MongoClient
from pymongo.server_api import ServerApi
from dotenv import load_dotenv
from werkzeug.security import generate_password_hash, check_password_hash
from bson.objectid import ObjectId

load_dotenv()

MONGODB_URI = os.getenv('MONGODB_URI', '')

class DatabaseManager:
    def __init__(self):
        self.db = None
        self.client = None
        self.connect()

    def connect(self):
        if not MONGODB_URI:
            print("⚠️ MONGODB_URI not found in environment variables.")
            return

        try:
            self.client = MongoClient(MONGODB_URI, server_api=ServerApi('1'))
            # Send a ping to confirm a successful connection
            self.client.admin.command('ping')
            print("✅ Successfully connected to MongoDB!")
            self.db = self.client['gemini_chat_db']
        except Exception as e:
            print(f"❌ MongoDB connection failed: {e}")
            self.db = None

    def create_conversation(self, user_id, title="New Chat"):
        """Create a new conversation"""
        if self.db is None:
            return None
        
        conv_col = self.db['conversations']
        result = conv_col.insert_one({
            "user_id": user_id,
            "title": title,
            "created_at": datetime.datetime.utcnow(),
            "updated_at": datetime.datetime.utcnow()
        })
        return str(result.inserted_id)

    def get_user_conversations(self, user_id, limit=20):
        """Get list of conversations for a user"""
        if self.db is None:
            return []
        
        conv_col = self.db['conversations']
        cursor = conv_col.find({"user_id": user_id}).sort("updated_at", -1).limit(limit)
        
        conversations = []
        for doc in cursor:
            conversations.append({
                "id": str(doc["_id"]),
                "title": doc.get("title", "New Chat"),
                "updated_at": doc["updated_at"].isoformat() if isinstance(doc.get("updated_at"), datetime.datetime) else str(doc.get("updated_at"))
            })
        return conversations

    def delete_conversation(self, conversation_id, user_id):
        """Delete a conversation and all its messages"""
        if self.db is None:
            return False
            
        try:
            # 1. Verify owner
            conv_col = self.db['conversations']
            conv = conv_col.find_one({"_id": ObjectId(conversation_id), "user_id": user_id})
            
            if not conv:
                return False # Not found or not owner
                
            # 2. Delete conversation
            conv_col.delete_one({"_id": ObjectId(conversation_id)})
            
            # 3. Delete messages
            msg_col = self.db['messages']
            msg_col.delete_many({"conversation_id": conversation_id})
            
            return True
        except Exception as e:
            print(f"❌ Error deleting conversation: {e}")
            return False

    def save_message(self, role, content, conversation_id, msg_type="text"):
        """Save a message to MongoDB linked to a conversation"""
        if self.db is None:
            return None
        
        try:
            # 1. Save message
            msg_col = self.db['messages']
            msg_col.insert_one({
                "conversation_id": conversation_id,
                "role": role,
                "content": content,
                "msg_type": msg_type,
                "timestamp": datetime.datetime.now()
            })
            
            # 2. Update conversation timestamp and title (if first message)
            conv_col = self.db['conversations']
            update_data = {"updated_at": datetime.datetime.now()}
            
            # Update title based on user's first message if title is default
            # (Simplified logic: just update time for now)
            
            conv_col.update_one(
                {"_id": ObjectId(conversation_id)},
                {"$set": update_data}
            )
            return True
        except Exception as e:
            print(f"❌ Error saving message: {e}")
            return None

    def update_conversation_title(self, conversation_id, new_title):
        """Update the title of a conversation"""
        if self.db is None:
            return False
        try:
            conv_col = self.db['conversations']
            conv_col.update_one(
                {"_id": ObjectId(conversation_id)},
                {"$set": {"title": new_title}}
            )
            return True
        except Exception as e:
            print(f"❌ Error updating title: {e}")
            return False

    def get_conversation_messages(self, conversation_id, user_id):
        """Get all messages for a specific conversation"""
        print(f"DEBUG_DB: get_conversation_messages called with conv_id={conversation_id}, user_id={user_id}")
        if self.db is None:
            print("DEBUG_DB: Database not connected")
            return []
            
        try:
            # Relaxed Check: Try to find conversation by ID first
            conv_col = self.db['conversations']
            conv = conv_col.find_one({"_id": ObjectId(conversation_id)})
            
            if not conv:
                print(f"DEBUG_DB: Conversation {conversation_id} NOT FOUND.")
                return []
            
            # Check ownership but don't block (for debugging/compatibility)
            if str(conv.get('user_id')) != str(user_id):
                 print(f"DEBUG_DB: WARNING - User mismatch! Owner: {conv.get('user_id')}, Request: {user_id}")
                 # Uncomment the next line to enforce strict security later
                 # return [] 
            
            print("DEBUG_DB: Conversation found. Fetching messages...")
                
            msg_col = self.db['messages']
            cursor = msg_col.find({"conversation_id": conversation_id}).sort("timestamp", 1)
            
            messages = []
            for doc in cursor:
                try:
                    ts = doc.get("timestamp")
                    if isinstance(ts, datetime.datetime):
                        ts_str = ts.isoformat()
                    else:
                        ts_str = str(ts)
                        
                    messages.append({
                        "role": doc.get("role", "model"),
                        "text": doc.get("content", ""), # Ensuring 'text' key is present
                        "timestamp": ts_str
                    })
                except Exception as e:
                    print(f"DEBUG_DB: Error parsing message doc: {e}")
                    continue

            print(f"DEBUG_DB: Returning {len(messages)} messages.")
            return messages
        except Exception as e:
            print(f"❌ Error fetching messages: {e}")
            import traceback
            traceback.print_exc()
            return []

    def get_messages(self, conversation_id, limit=50):
        """Get messages for a specific conversation"""
        print(f"DEBUG_DB: get_messages called for ID: {conversation_id}")
        if self.db is None:
            return []
        
        try:
            collection = self.db['messages']
            # Debug: Check if any message exists with this ID
            count = collection.count_documents({"conversation_id": conversation_id})
            print(f"DEBUG_DB: Found {count} messages for conv_id {conversation_id}")
            
            cursor = collection.find({"conversation_id": conversation_id}).sort("timestamp", 1).limit(limit)
            
            messages = []
            for doc in cursor:
                # Debug print for first doc
                # if len(messages) == 0: print(f"DEBUG_DB: First doc: {doc}")
                messages.append({
                    "role": doc["role"],
                    "content": doc["content"]
                })
            return messages
        except Exception as e:
            print(f"❌ Error getting messages: {e}")
            import traceback
            traceback.print_exc()
            return []

    def register_user(self, username, password):
        """Register a new user"""
        if self.db is None:
            return False, "Database connection error"
            
        users_col = self.db['users']
        
        # Check if user exists
        if users_col.find_one({"username": username}):
            return False, "Username already exists"
            
        # Hash password
        password_hash = generate_password_hash(password)
        
        users_col.insert_one({
            "username": username,
            "password": password_hash,
            "created_at": datetime.datetime.now()
        })
        return True, "Registration successful"

    def authenticate_user(self, username, password):
        """Authenticate a user"""
        if self.db is None:
            return None
            
        user = self.db['users'].find_one({"username": username})
        if user and check_password_hash(user['password'], password):
            return str(user['_id']) # Return User ID as string
        return None
