import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

class WebRtcSignalingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Creates a WebRTC PeerConnection with Google STUN servers.
  Future<RTCPeerConnection> createConnection() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]
    };
    return await createPeerConnection(configuration);
  }

  /// Sends an SDP Offer (Caller/Camera Node).
  Future<void> sendOffer(String instructorId, RTCSessionDescription offer) async {
    await _db.collection('live_sessions').doc(instructorId).set({
      'webrtcOffer': offer.toMap(),
    }, SetOptions(merge: true));
  }

  /// Sends an SDP Answer (Callee/Remote Control Node).
  Future<void> sendAnswer(String instructorId, RTCSessionDescription answer) async {
    await _db.collection('live_sessions').doc(instructorId).set({
      'webrtcAnswer': answer.toMap(),
    }, SetOptions(merge: true));
  }

  /// Listens for an SDP Answer (Caller).
  Stream<RTCSessionDescription?> watchAnswer(String instructorId) {
    return _db.collection('live_sessions').doc(instructorId).snapshots().map((snap) {
      final data = snap.data();
      if (data != null && data.containsKey('webrtcAnswer')) {
        return RTCSessionDescription(
          data['webrtcAnswer']['sdp'],
          data['webrtcAnswer']['type'],
        );
      }
      return null;
    });
  }

  /// Listens for an SDP Offer (Callee).
  Stream<RTCSessionDescription?> watchOffer(String instructorId) {
    return _db.collection('live_sessions').doc(instructorId).snapshots().map((snap) {
      final data = snap.data();
      if (data != null && data.containsKey('webrtcOffer')) {
        return RTCSessionDescription(
          data['webrtcOffer']['sdp'],
          data['webrtcOffer']['type'],
        );
      }
      return null;
    });
  }

  /// Sends an ICE Candidate.
  Future<void> sendIceCandidate(String instructorId, String sender, RTCIceCandidate candidate) async {
    await _db
        .collection('live_sessions')
        .doc(instructorId)
        .collection('ice_candidates')
        .add({
      'sender': sender, // 'camera' or 'remote'
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  }

  /// Listens for ICE Candidates from the OTHER peer.
  Stream<List<RTCIceCandidate>> watchIceCandidates(String instructorId, String otherSender) {
    return _db
        .collection('live_sessions')
        .doc(instructorId)
        .collection('ice_candidates')
        .where('sender', isEqualTo: otherSender)
        .snapshots()
        .map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data();
        return RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );
      }).toList();
    });
  }

  /// Clears the WebRTC signaling data.
  Future<void> clearSignaling(String instructorId) async {
    // Delete candidates subcollection
    final candidates = await _db
        .collection('live_sessions')
        .doc(instructorId)
        .collection('ice_candidates')
        .get();
    
    for (var doc in candidates.docs) {
      await doc.reference.delete();
    }

    // Remove offer and answer from main doc
    await _db.collection('live_sessions').doc(instructorId).update({
      'webrtcOffer': FieldValue.delete(),
      'webrtcAnswer': FieldValue.delete(),
    });
  }
}
