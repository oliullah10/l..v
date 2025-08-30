import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lawvico/Pages/UserProfileViewPage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPage extends StatefulWidget {
  final String currentUserId;
  final String receiverId;
  final String receiverName;
  

  const ChatPage({
    Key? key,
    required this.currentUserId,
    required this.receiverId,
    required this.receiverName,
  }) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late Future<void> _chatInitFuture;
  final FocusNode _focusNode = FocusNode();
  File? _selectedImage;
  String get chatId {
    final ids = [widget.currentUserId, widget.receiverId]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  @override
  void initState() {
    super.initState();
    _chatInitFuture = _ensureChatExists();
    _chatInitFuture.then((_) => _markMessagesAsRead());
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

 Future<void> _imageUse() async {
  try {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  } catch (e) {
    debugPrint("❌ Error picking image: $e");
  }
}



  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _scrollToBottom();
    }
  }

  Future<void> _ensureChatExists() async {
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
    final snapshot = await chatRef.get();

    if (!snapshot.exists) {
      await chatRef.set({
        'participants': [widget.currentUserId, widget.receiverId],
        'lastMessage': '',
        'lastTimestamp': Timestamp.now(),
        'unreadCounts': {
          widget.currentUserId: 0,
          widget.receiverId: 0,
        },
      });
    }
  }

  Future<void> _markMessagesAsRead() async {
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
    final snapshot = await chatRef.get();

    if (snapshot.exists) {
      final data = snapshot.data() as Map<String, dynamic>;
      final unreadCounts = Map<String, dynamic>.from(data['unreadCounts'] ?? {});
      if (unreadCounts[widget.currentUserId] != 0) {
        unreadCounts[widget.currentUserId] = 0;
        await chatRef.update({'unreadCounts': unreadCounts});
      }
    }
  }
Future<void> _sendMessage() async {
  final text = _controller.text.trim();

  // Text empty & image na thakle return
  if (text.isEmpty && _selectedImage == null) return;

  final timestamp = Timestamp.now();
  final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

  final currentUser = FirebaseAuth.instance.currentUser;
  String senderName = "Someone";

  if (currentUser != null) {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    if (userDoc.exists) {
      final userData = userDoc.data();
      if (userData != null && userData['name'] != null) {
        senderName = userData['name'];
      }
    }
  }

  // Handle optional image upload
  String? imageUrl;
  if (_selectedImage != null) {
    final supabase = Supabase.instance.client;
    final fileName =
        'premium/${DateTime.now().millisecondsSinceEpoch}_${_selectedImage!.path.split('/').last}';
    final res = await supabase.storage.from('profiles').upload(fileName, _selectedImage!);

    if (res.isNotEmpty) {
      imageUrl = supabase.storage.from('profiles').getPublicUrl(fileName);
    }
  }

  // Chat document update
  final snapshot = await chatRef.get();
  if (!snapshot.exists) {
    await chatRef.set({
      'participants': [widget.currentUserId, widget.receiverId],
      'lastMessage': text.isNotEmpty ? text : '📷 Image',
      'lastTimestamp': timestamp,
      'unreadCounts': {
        widget.currentUserId: 0,
        widget.receiverId: 1,
      },
    });
  } else {
    final data = snapshot.data() as Map<String, dynamic>;
    final unreadCounts = Map<String, dynamic>.from(data['unreadCounts'] ?? {});
    unreadCounts[widget.receiverId] = (unreadCounts[widget.receiverId] ?? 0) + 1;

    await chatRef.update({
      'lastMessage': text.isNotEmpty ? text : '📷 Image',
      'lastTimestamp': timestamp,
      'unreadCounts': unreadCounts,
    });
  }

  // Add message with optional imageUrl
  await chatRef.collection('messages').add({
    'senderId': widget.currentUserId,
    'text': text,
    'imageUrl': imageUrl ?? '',
    'timestamp': timestamp,
  });

  // Clear input & selected image
  _controller.clear();
  setState(() {
    _selectedImage = null;
  });
  _scrollToBottom();

  // Send notification
  if (widget.receiverId != widget.currentUserId) {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(widget.receiverId)
        .collection('items')
        .add({
      'title': 'New Message',
      'message': text.isNotEmpty ? '$senderName: $text' : '$senderName sent an image',
      'chatId': chatId,
      'senderId': widget.currentUserId,
      'senderName': senderName,
      'timestamp': timestamp,
      'seen': false,
    });
  }
}



  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(widget.receiverName,style: TextStyle(color: Colors.white),),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileViewPage(userId: widget.receiverId),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
  child: FutureBuilder<void>(
    future: _chatInitFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      } else if (snapshot.hasError) {
        return const Center(child: Text('Failed to load chat'));
      }

      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .orderBy('timestamp', descending: true) // latest first for reverse:true
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Say hi 👋"));
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            controller: _scrollController,
            reverse: true, // keep newest message at bottom
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final msg = docs[index].data() as Map<String, dynamic>;
              final isMe = msg['senderId'] == widget.currentUserId;
              final text = msg['text'] ?? '';

              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.orange : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    },
  ),
),

            SafeArea(
  child: Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom + 8, 
      left: 8,
      right: 8,
      top: 8,
    ),
    child:StreamBuilder<DocumentSnapshot>(
  stream: FirebaseFirestore.instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser!.uid)
      .snapshots(),
  builder: (context, snapshot) {
    if (!snapshot.hasData) return SizedBox();

    final userData = snapshot.data!.data() as Map<String, dynamic>;
    final canUseImage = userData['image_use'] ?? false;

    return Row(
      children: [
        if (canUseImage)
      IconButton(
        onPressed: _imageUse,
        icon: const Icon(Icons.image, color: Colors.orange),
      ),

    // Show selected image preview if any
    if (_selectedImage != null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Stack(
          children: [
            Image.file(
              _selectedImage!,
              width: 150,
              height: 150,
              fit: BoxFit.cover,
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => setState(() => _selectedImage = null),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            )
          ],
        ),
      ),
        
        
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Type a message...',
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _sendMessage,
          icon: const Icon(Icons.send, color: Colors.orange),
        ),
      ],
    );
  },
)

  ),
),

          ],
        ),
      ),
    );
  }
}
