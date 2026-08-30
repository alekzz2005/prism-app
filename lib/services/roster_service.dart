import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart';

class StudentRoster {
  final String id;
  final String firstName;
  final String lastName;
  final String middleInitial;
  final String email;
  final bool isArchived;

  StudentRoster({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleInitial = '',
    required this.email,
    this.isArchived = false,
  });

  factory StudentRoster.fromMap(String id, Map<String, dynamic> data) {
    return StudentRoster(
      id: id,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      middleInitial: data['middleInitial'] ?? '',
      email: data['email'] ?? '',
      isArchived: data['isArchived'] ?? false,
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String get formattedFullName {
    final last = _capitalize(lastName);
    final first = _capitalize(firstName);
    String mi = middleInitial.trim().toUpperCase();
    if (mi.isNotEmpty) {
      if (!mi.endsWith('.')) {
        mi = '$mi.';
      }
      return '$last, $first $mi';
    }
    return '$last, $first';
  }

  Map<String, dynamic> toMap() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'middleInitial': middleInitial,
      'email': email,
    };
  }
}

class InstructorSection {
  final String id;
  final String name;
  final String schoolYear;

  InstructorSection({required this.id, required this.name, required this.schoolYear});

  factory InstructorSection.fromMap(String id, Map<String, dynamic> data) {
    String rawName = data['name'] as String? ?? id;
    if (rawName.contains('_')) {
      rawName = rawName.split('_').first;
    }
    return InstructorSection(
      id: id,
      name: rawName,
      schoolYear: data['schoolYear'] ?? 'Default',
    );
  }
}

class RosterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Fetches sections for the instructor.
  Stream<List<InstructorSection>> watchSections(String instructorId) {
    return _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => InstructorSection.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Fetches the roster for the instructor's section.
  Stream<List<StudentRoster>> watchRoster(String instructorId, String sectionName, {bool includeArchived = false}) {
    return _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .doc(sectionName)
        .collection('students')
        .orderBy('lastName')
        .snapshots()
        .map((snap) {
          var students = snap.docs.map((doc) => StudentRoster.fromMap(doc.id, doc.data())).toList();
          if (!includeArchived) {
            students = students.where((s) => !s.isArchived).toList();
          }
          return students;
        });
  }

  /// Adds a single student to the given section's roster.
  Future<void> addStudent(
    String instructorId,
    String sectionName, {
    required String firstName,
    required String lastName,
    required String middleInitial,
    required String email,
  }) async {
    final studentsRef = _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .doc(sectionName)
        .collection('students');
        
    final e = email.trim().toLowerCase();
    if (e.isNotEmpty && !e.endsWith('@gmail.com')) {
      throw 'Email address must end with @gmail.com';
    }
    
    // Check for duplicate email among active students
    final snap = await studentsRef.get();
    for (var doc in snap.docs) {
      final docE = (doc.data()['email'] as String?)?.trim().toLowerCase() ?? '';
      final isArchived = doc.data()['isArchived'] as bool? ?? false;
      if (!isArchived && e.isNotEmpty && e == docE) {
        throw 'A student with this email already exists in this section.';
      }
    }

    // Ensure the parent section document exists
    await _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .doc(sectionName)
        .set({'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

    await studentsRef.add({
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'middleInitial': middleInitial.trim(),
      'email': e,
      'isArchived': false,
    });
  }

  /// Updates an existing student's details in the given section's roster.
  Future<void> updateStudent(
    String instructorId,
    String sectionName,
    String studentId, {
    required String firstName,
    required String lastName,
    required String middleInitial,
    required String email,
  }) async {
    final studentsRef = _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .doc(sectionName)
        .collection('students');

    final e = email.trim().toLowerCase();
    if (e.isNotEmpty && !e.endsWith('@gmail.com')) {
      throw 'Email address must end with @gmail.com';
    }

    // Check for duplicate email among other active students
    final snap = await studentsRef.get();
    for (var doc in snap.docs) {
      if (doc.id == studentId) continue;
      final docE = (doc.data()['email'] as String?)?.trim().toLowerCase() ?? '';
      final isArchived = doc.data()['isArchived'] as bool? ?? false;
      if (!isArchived && e.isNotEmpty && e == docE) {
        throw 'Another active student in this section already has the email "$e".';
      }
    }

    await studentsRef.doc(studentId).update({
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'middleInitial': middleInitial.trim(),
      'email': e,
    });
  }

  /// Parses a spreadsheet file (CSV, XLSX, XLS) and uploads to the roster section.
  Future<void> importRoster(String instructorId, String sectionName, Uint8List fileBytes, String fileName) async {
    try {
      final ext = fileName.split('.').last.toLowerCase();
      List<List<String>> rows;

      if (ext == 'csv') {
        final csvString = utf8.decode(fileBytes);
        rows = const CsvDecoder()
            .convert(csvString)
            .map((r) => r.map((e) => e.toString()).toList())
            .toList();
      } else if (ext == 'xlsx' || ext == 'xls') {
        final excel = xl.Excel.decodeBytes(fileBytes);
        final sheet = excel.tables[excel.tables.keys.first]!;
        rows = sheet.rows
            .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
            .toList();
      } else {
        throw Exception('Unsupported file format. Please use CSV, XLSX, or XLS.');
      }

      if (rows.isEmpty) return;

      final headers = rows.first.map((e) => e.toLowerCase().trim()).toList();

      int firstNameIdx = headers.indexWhere((h) => h.contains('first'));
      int lastNameIdx = headers.indexWhere((h) => h.contains('last'));
      int middleIdx = headers.indexWhere((h) =>
          h.contains('middle initial') || h.contains('middle') || h.contains('initial') ||
          h == 'm.i.' || h == 'mi' || h == 'm.i');
      int emailIdx = headers.indexWhere((h) => h.contains('email'));

      // Fallbacks if no exact header match
      if (firstNameIdx == -1) firstNameIdx = 0;
      if (lastNameIdx == -1) lastNameIdx = (middleIdx != -1) ? 2 : 1;
      if (emailIdx == -1) emailIdx = (middleIdx != -1) ? 3 : 2;

      final batch = _db.batch();
      final collRef = _db
          .collection('instructor_roster')
          .doc(instructorId)
          .collection('sections')
          .doc(sectionName)
          .collection('students');

      // Ensure the section doc exists with name if it doesn't have one
      batch.set(
        _db.collection('instructor_roster').doc(instructorId).collection('sections').doc(sectionName),
        {
          'createdAt': FieldValue.serverTimestamp(),
          'name': sectionName,
        },
        SetOptions(merge: true),
      );

      // Fetch existing students to check for duplicates
      final existing = await collRef.get();
      final existingEmails = existing.docs.map((d) {
        return (d.data()['email'] as String?)?.trim().toLowerCase() ?? '';
      }).where((e) => e.isNotEmpty).toSet();
      
      final existingNames = existing.docs.map((d) {
        final f = (d.data()['firstName'] as String?)?.trim().toLowerCase() ?? '';
        final l = (d.data()['lastName'] as String?)?.trim().toLowerCase() ?? '';
        return '$f|$l';
      }).toSet();

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length <= emailIdx) continue; // skip malformed rows
        
        final fName = row[firstNameIdx].trim();
        final lName = row[lastNameIdx].trim();
        final email = row[emailIdx].trim().toLowerCase();
        
        if (fName.isEmpty && lName.isEmpty) continue; // skip empty rows

        // Check if this student is already in the database
        if (email.isNotEmpty) {
          if (existingEmails.contains(email)) continue;
          existingEmails.add(email);
        } else {
          final nameKey = '${fName.toLowerCase()}|${lName.toLowerCase()}';
          if (existingNames.contains(nameKey)) continue;
          existingNames.add(nameKey);
        }

        String mi = middleIdx != -1 && row.length > middleIdx ? row[middleIdx].trim() : '';

        final docRef = collRef.doc(); // auto-ID
        batch.set(docRef, {
          'firstName': fName,
          'lastName': row[lastNameIdx].trim(),
          'middleInitial': mi,
          'email': row[emailIdx].trim().toLowerCase(), // Force lowercase for reliable querying
        });
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error importing roster: $e');
      rethrow;
    }
  }

  /// Updates a section's name and school year, and cascades the name update to all related sessions.
  Future<void> updateSection(String instructorId, String sectionId, String oldName, String newName, String newSchoolYear) async {
    final batch = _db.batch();

    // 1. Update the section document
    final sectionRef = _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .doc(sectionId);
    
    batch.set(sectionRef, {
      'name': newName.trim(),
      'schoolYear': newSchoolYear.trim(),
    }, SetOptions(merge: true));

    // 2. Cascade name change to all sessions matching the old name
    if (oldName != newName.trim()) {
      final sessionsQuery = await _db.collection('sessions').where('sectionName', isEqualTo: oldName).get();
      for (var doc in sessionsQuery.docs) {
        batch.update(doc.reference, {'sectionName': newName.trim()});
      }
    }

    await batch.commit();
  }

  /// Archives a student by flagging them in the section's roster.
  Future<void> archiveStudent(String instructorId, String sectionName, String studentId) async {
    await _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .doc(sectionName)
        .collection('students')
        .doc(studentId)
        .update({'isArchived': true});
  }

  /// Restores an archived student in the section's roster.
  Future<void> unarchiveStudent(String instructorId, String sectionName, String studentId) async {
    final studentsRef = _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .doc(sectionName)
        .collection('students');

    final studentDoc = await studentsRef.doc(studentId).get();
    if (!studentDoc.exists) return;
    final targetEmail = (studentDoc.data()?['email'] as String?)?.trim().toLowerCase() ?? '';

    // Check for email conflicts among active students
    if (targetEmail.isNotEmpty) {
      final activeSnap = await studentsRef.where('isArchived', isEqualTo: false).get();
      for (var doc in activeSnap.docs) {
        if (doc.id == studentId) continue;
        final docE = (doc.data()['email'] as String?)?.trim().toLowerCase() ?? '';
        if (docE == targetEmail) {
          throw 'Cannot restore: An active student with email "$targetEmail" already exists in this section.';
        }
      }
    }

    await studentsRef.doc(studentId).update({'isArchived': false});
  }

  /// Permanently deletes all archived students in the section.
  Future<int> deleteAllArchivedStudents(String instructorId, String sectionName) async {
    final studentsRef = _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .doc(sectionName)
        .collection('students');

    final snap = await studentsRef.where('isArchived', isEqualTo: true).get();
    if (snap.docs.isEmpty) return 0;

    final batch = _db.batch();
    for (var doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    return snap.docs.length;
  }
}
