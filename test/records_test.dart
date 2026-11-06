// Test doubles isolate stream switching without connecting to Firestore.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuk_kasir/screens.dart';

class TestQuery extends Fake implements Query<Map<String, dynamic>> {
  final controller =
      StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => controller.stream;
}

class TestSnapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  TestSnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

class TestDocument extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  TestDocument(this.values);
  final Map<String, dynamic> values;
  @override
  Map<String, dynamic> data() => values;
}

void main() {
  testWidgets(
    'changing records query does not send customer data to service builder',
    (tester) async {
      final customers = TestQuery(), services = TestQuery();
      Widget page(TestQuery query, bool service) => MaterialApp(
        home: Scaffold(
          body: Records(
            query: query,
            builder: (docs) => Text(
              service
                  ? docs.first.data()['values'][0] as String
                  : docs.first.data()['name'] as String,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(customers, false));
      customers.controller.add(
        TestSnapshot([
          TestDocument({'name': 'Customer'}),
        ]),
      );
      await tester.pump();
      expect(find.text('Customer'), findsOneWidget);
      await tester.pumpWidget(page(services, true));
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      services.controller.add(
        TestSnapshot([
          TestDocument({
            'values': ['Laundry'],
          }),
        ]),
      );
      await tester.pump();
      expect(find.text('Laundry'), findsOneWidget);
      await tester.pumpWidget(page(customers, false));
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await customers.controller.close();
      await services.controller.close();
    },
  );
}
