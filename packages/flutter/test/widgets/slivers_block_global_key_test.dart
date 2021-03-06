// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

int globalGeneration = 0;

class GenerationText extends StatefulWidget {
  GenerationText(this.value);
  final int value;
  @override
  _GenerationTextState createState() => new _GenerationTextState();
}

class _GenerationTextState extends State<GenerationText> {
  _GenerationTextState() : generation = globalGeneration;
  final int generation;
  @override
  Widget build(BuildContext context) => new Text('${config.value}:$generation ');
}

Future<Null> test(WidgetTester tester, double offset, List<int> keys) {
  globalGeneration += 1;
  return tester.pumpWidget(new Viewport2(
    offset: new ViewportOffset.fixed(offset),
    slivers: <Widget>[
      new SliverList(
        delegate: new SliverChildListDelegate(keys.map((int key) {
          return new SizedBox(key: new GlobalObjectKey(key), height: 100.0, child: new GenerationText(key));
        }).toList()),
      ),
    ],
  ));
}

void verify(WidgetTester tester, List<Point> answerKey, String text) {
  List<Point> testAnswers = tester.renderObjectList<RenderBox>(find.byType(SizedBox)).map<Point>(
    (RenderBox target) => target.localToGlobal(const Point(0.0, 0.0))
  ).toList();
  expect(testAnswers, equals(answerKey));
  final String foundText =
    tester.widgetList<Text>(find.byType(Text))
    .map<String>((Text widget) => widget.data)
    .reduce((String value, String element) => value + element);
  expect(foundText, equals(text));
}

void main() {
  testWidgets('Viewport2+SliverBlock with GlobalKey reparenting', (WidgetTester tester) async {
    await test(tester, 0.0, <int>[1,2,3,4,5,6,7,8,9]);
    verify(tester, <Point>[
      const Point(0.0, 0.0),
      const Point(0.0, 100.0),
      const Point(0.0, 200.0),
      const Point(0.0, 300.0),
      const Point(0.0, 400.0),
      const Point(0.0, 500.0),
    ], '1:1 2:1 3:1 4:1 5:1 6:1 ');
    // gen 2 - flipping the order:
    await test(tester, 0.0, <int>[9,8,7,6,5,4,3,2,1]);
    verify(tester, <Point>[
      const Point(0.0, 0.0),
      const Point(0.0, 100.0),
      const Point(0.0, 200.0),
      const Point(0.0, 300.0),
      const Point(0.0, 400.0),
      const Point(0.0, 500.0),
    ], '9:2 8:2 7:2 6:1 5:1 4:1 ');
    // gen 3 - flipping the order back:
    await test(tester, 0.0, <int>[1,2,3,4,5,6,7,8,9]);
    verify(tester, <Point>[
      const Point(0.0, 0.0),
      const Point(0.0, 100.0),
      const Point(0.0, 200.0),
      const Point(0.0, 300.0),
      const Point(0.0, 400.0),
      const Point(0.0, 500.0),
    ], '1:3 2:3 3:3 4:1 5:1 6:1 ');
    // gen 4 - removal:
    await test(tester, 0.0, <int>[1,2,3,5,6,7,8,9]);
    verify(tester, <Point>[
      const Point(0.0, 0.0),
      const Point(0.0, 100.0),
      const Point(0.0, 200.0),
      const Point(0.0, 300.0),
      const Point(0.0, 400.0),
      const Point(0.0, 500.0),
    ], '1:3 2:3 3:3 5:1 6:1 7:4 ');
    // gen 5 - insertion:
    await test(tester, 0.0, <int>[1,2,3,4,5,6,7,8,9]);
    verify(tester, <Point>[
      const Point(0.0, 0.0),
      const Point(0.0, 100.0),
      const Point(0.0, 200.0),
      const Point(0.0, 300.0),
      const Point(0.0, 400.0),
      const Point(0.0, 500.0),
    ], '1:3 2:3 3:3 4:5 5:1 6:1 ');
    // gen 6 - adjacent reordering:
    await test(tester, 0.0, <int>[1,2,3,5,4,6,7,8,9]);
    verify(tester, <Point>[
      const Point(0.0, 0.0),
      const Point(0.0, 100.0),
      const Point(0.0, 200.0),
      const Point(0.0, 300.0),
      const Point(0.0, 400.0),
      const Point(0.0, 500.0),
    ], '1:3 2:3 3:3 5:1 4:5 6:1 ');
    // gen 7 - scrolling:
    await test(tester, 120.0, <int>[1,2,3,5,4,6,7,8,9]);
    verify(tester, <Point>[
      const Point(0.0, -20.0),
      const Point(0.0, 80.0),
      const Point(0.0, 180.0),
      const Point(0.0, 280.0),
      const Point(0.0, 380.0),
      const Point(0.0, 480.0),
      const Point(0.0, 580.0),
    ], '2:3 3:3 5:1 4:5 6:1 7:7 8:7 ');
  });
}
