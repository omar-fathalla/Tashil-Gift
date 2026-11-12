// Dry-run by default. This script does not write Firestore unless both
// --commit and TASHIL_ALLOW_SUPERVISOR_IMPORT=yes are set, after the owner
// approves a production import.
//
//   dart run tool/import_company_supervisors.dart
//   dart run tool/import_company_supervisors.dart --commit
//   dart run tool/import_company_supervisors.dart --commit --replace
//
// --replace deletes stored supervisors whose mobiles are absent from the file.
import 'dart:convert';
import 'dart:io';

import 'package:al_mraay/features/company_portal/domain/company_supervisor_import.dart';

const _projectId = 'tashil-gift';

Future<void> main(List<String> args) async {
  final commit = args.contains('--commit');
  final replace = args.contains('--replace');
  final fileFlag = _flagValue(args, '--file');
  final path = fileFlag ?? 'tool/seeds/company-supervisors.xlsx';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Workbook not found: $path');
    exit(1);
  }

  final result = parseCompanySupervisorWorkbook(
    file.readAsBytesSync(),
    fileName: file.uri.pathSegments.isEmpty ? path : file.uri.pathSegments.last,
  );
  if (result.errorMessage != null) {
    stderr.writeln(result.errorMessage);
    exit(1);
  }

  stdout.writeln('Source rows: ${result.sourceRowCount}');
  stdout.writeln('Unique mobiles: ${result.uniqueCount}');
  stdout.writeln('Duplicate rows collapsed: ${result.duplicateRowCount}');
  stdout.writeln('Invalid rows: ${result.invalidRowCount}');
  stdout.writeln('Duplicate phone groups: ${result.duplicateGroups.length}');
  for (final group in result.duplicateGroups) {
    final alternates = group.alternateNames.isEmpty ? '(none)' : group.alternateNames.join(' | ');
    stdout.writeln('  ${group.mobile} kept "${group.keptName}" alternate: $alternates');
  }

  final mobiles = result.supervisors.map((supervisor) => supervisor.mobile).toSet();
  for (final requiredMobile in ['01099999997', '01234567890']) {
    stdout.writeln(mobiles.contains(requiredMobile)
        ? 'Kept provided row $requiredMobile'
        : 'MISSING provided row $requiredMobile');
  }

  if (!commit) {
    stdout.writeln('Dry run only. No Firestore writes.');
    exit(mobiles.contains('01099999997') && mobiles.contains('01234567890') ? 0 : 1);
  }

  if (Platform.environment['TASHIL_ALLOW_SUPERVISOR_IMPORT'] != 'yes') {
    stderr.writeln(
      'Refusing to write. Set TASHIL_ALLOW_SUPERVISOR_IMPORT=yes after owner approval, then re-run with --commit.',
    );
    exit(2);
  }

  final token = _accessToken();
  await _upsert(token, result.supervisors);
  if (replace) {
    await _deleteMissing(token, mobiles);
  }
  stdout.writeln('Wrote ${result.uniqueCount} company supervisors.');
}

String? _flagValue(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _accessToken() {
  final result = Process.runSync('gcloud', ['auth', 'print-access-token']);
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    exit(1);
  }
  final token = (result.stdout as String).trim();
  if (token.isEmpty) {
    stderr.writeln('gcloud did not return an access token.');
    exit(1);
  }
  return token;
}

Future<void> _upsert(String token, List<ImportedCompanySupervisor> supervisors) async {
  final client = HttpClient();
  try {
    for (final supervisor in supervisors) {
      final uri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/$companySupervisorsCollection/${supervisor.mobile}',
      );
      final request = await client.patchUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode({'fields': _fields(supervisor)})));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        stderr.writeln('Failed ${supervisor.mobile}: ${response.statusCode} $body');
        exit(1);
      }
    }
  } finally {
    client.close();
  }
}

Future<void> _deleteMissing(String token, Set<String> keep) async {
  final client = HttpClient();
  try {
    var pageToken = '';
    while (true) {
      final query = pageToken.isEmpty ? '' : '?pageToken=$pageToken';
      final uri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/$companySupervisorsCollection$query',
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        stderr.writeln('List failed: ${response.statusCode} $body');
        exit(1);
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return;
      final documents = decoded['documents'];
      if (documents is List) {
        for (final document in documents) {
          if (document is! Map) continue;
          final name = document['name']?.toString() ?? '';
          final id = name.split('/').last;
          if (id.isEmpty || keep.contains(id)) continue;
          final deleteUri = Uri.parse('https://firestore.googleapis.com/v1/$name');
          final deleteRequest = await client.deleteUrl(deleteUri);
          deleteRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          final deleteResponse = await deleteRequest.close();
          await deleteResponse.drain();
          if (deleteResponse.statusCode < 200 || deleteResponse.statusCode >= 300) {
            stderr.writeln('Delete failed for $id: ${deleteResponse.statusCode}');
            exit(1);
          }
        }
      }
      final next = decoded['nextPageToken']?.toString() ?? '';
      if (next.isEmpty) return;
      pageToken = next;
    }
  } finally {
    client.close();
  }
}

Map<String, dynamic> _fields(ImportedCompanySupervisor supervisor) {
  return {
    'name': {'stringValue': supervisor.name},
    'alternateNames': {
      'arrayValue': {
        'values': [
          for (final name in supervisor.alternateNames) {'stringValue': name},
        ],
      },
    },
    'mobile': {'stringValue': supervisor.mobile},
    'cleanPhone': {'stringValue': supervisor.cleanPhone},
    'source': {'stringValue': supervisor.source},
    'audience': {'stringValue': companySupervisorsAudience},
  };
}
