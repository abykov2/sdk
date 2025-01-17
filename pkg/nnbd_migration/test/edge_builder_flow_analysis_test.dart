// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'migration_visitor_test_base.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(EdgeBuilderFlowAnalysisTest);
  });
}

@reflectiveTest
class EdgeBuilderFlowAnalysisTest extends EdgeBuilderTestBase {
  test_assignmentExpression() async {
    await analyze('''
void f(int i, int j) {
  if (i != null) {
    g(i);
    i = j;
    h(i);
  }
}
void g(int k) {}
void h(int l) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    var lNode = decoratedTypeAnnotation('int l').node;
    // No edge from i to k because i's type is promoted to non-nullable
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to l, because it is after the assignment
    assertEdge(iNode, lNode, hard: false);
    // And there is an edge from j to i, because a null value of j would lead to
    // a null value for i.
    assertEdge(jNode, iNode, hard: false);
  }

  test_assignmentExpression_lhs_before_rhs() async {
    await analyze('''
void f(int i, List<int> l) {
  if (i != null) {
    l[i = g(i)] = h(i);
  }
}
int g(int j) => 1;
int h(int k) => 1;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    var gReturnNode = decoratedTypeAnnotation('int g').node;
    // No edge from i to j, because i's type is promoted before the call to g.
    assertNoEdge(iNode, jNode);
    // But there is an edge from i to k, because the call to h happens after the
    // assignment.
    assertEdge(iNode, kNode, hard: false);
    // And there is an edge from g's return type to i, due to the assignment.
    assertEdge(gReturnNode, iNode, hard: false);
  }

  test_assignmentExpression_write_after_rhs() async {
    await analyze('''
void f(int i) {
  if (i != null) {
    i = g(i);
    h(i);
  }
}
int g(int j) => 1;
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    var gReturnNode = decoratedTypeAnnotation('int g').node;
    // No edge from i to j because i's type is promoted before the call to g.
    assertNoEdge(iNode, jNode);
    // But there is an edge from i to k, because the call to h happens after the
    // assignment.
    assertEdge(iNode, kNode, hard: false);
    // And there is an edge from g's return type to i, due to the assignment.
    assertEdge(gReturnNode, iNode, hard: false);
  }

  test_binaryExpression_ampersandAmpersand_left() async {
    await analyze('''
bool f(int i) => i != null && i.isEven;
bool g(int j) => j.isEven;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: true);
  }

  test_binaryExpression_ampersandAmpersand_right() async {
    await analyze('''
void f(bool b, int i, int j) {
  if (b && i != null) {
    print(i.isEven);
    print(j.isEven);
  }
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: false);
  }

  test_binaryExpression_barBar_left() async {
    await analyze('''
bool f(int i) => i == null || i.isEven;
bool g(int j) => j.isEven;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: true);
  }

  test_binaryExpression_barBar_right() async {
    await analyze('''
void f(bool b, int i, int j) {
  if (b || i == null) {} else {
    print(i.isEven);
    print(j.isEven);
  }
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: false);
  }

  test_booleanLiteral_false() async {
    await analyze('''
void f(int i, int j) {
  if (i != null || false) {} else return;
  if (j != null || true) {} else return;
  i.isEven;
  j.isEven;
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never i is known to be non-nullable at the site of
    // the call to i.isEven
    assertNoEdge(iNode, never);
    // But there is an edge from j to never
    assertEdge(jNode, never, hard: false);
  }

  test_booleanLiteral_true() async {
    await analyze('''
void f(int i, int j) {
  if (i == null && true) return;
  if (j == null && false) return;
  i.isEven;
  j.isEven;
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never i is known to be non-nullable at the site of
    // the call to i.isEven
    assertNoEdge(iNode, never);
    // But there is an edge from j to never
    assertEdge(jNode, never, hard: false);
  }

  test_break_labeled() async {
    await analyze('''
void f(int i) {
  L: while(true) {
    while (b()) {
      if (i != null) break L;
    }
    g(i);
  }
  h(i);
}
bool b() => true;
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is promoted at the time of the call to h.
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j, because i is not promoted at the time
    // of the call to g.
    assertEdge(iNode, jNode, hard: false);
  }

  test_break_unlabeled() async {
    await analyze('''
void f(int i) {
  while (true) {
    if (i != null) break;
    g(i);
  }
  h(i);
}
bool b() => true;
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is promoted at the time of the call to h.
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j, because i is not promoted at the time
    // of the call to g.
    assertEdge(iNode, jNode, hard: false);
  }

  test_conditionalExpression() async {
    await analyze('''
int f(int i) => i == null ? g(i) : h(i);
int g(int j) => 1;
int h(int k) => 1;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is known to be non-nullable at the site of
    // the call to h()
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j
    // TODO(paulberry): there should be a guard on this edge.
    assertEdge(iNode, jNode, hard: false);
  }

  test_conditionalExpression_propagates_promotions() async {
    await analyze('''
void f(bool b, int i, int j, int k) {
  if (b ? (i != null && j != null) : (i != null && k != null)) {
    i.isEven;
    j.isEven;
    k.isEven;
  }
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to never because i is promoted.
    assertNoEdge(iNode, never);
    // But there are edges from j and k to never.
    assertEdge(jNode, never, hard: false);
    assertEdge(kNode, never, hard: false);
  }

  test_constructorDeclaration_assert() async {
    await analyze('''
class C {
  C(int i, int j) : assert(i == null || i.isEven, j.isEven);
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: true);
  }

  test_constructorDeclaration_initializer() async {
    await analyze('''
class C {
  bool b1;
  bool b2;
  C(int i, int j) : b1 = i == null || i.isEven, b2 = j.isEven;
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: true);
  }

  test_constructorDeclaration_redirection() async {
    await analyze('''
class C {
  C(bool b1, bool b2);
  C.redirect(int i, int j) : this(i == null || i.isEven, j.isEven);
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: true);
  }

  test_continue_labeled() async {
    await analyze('''
void f(int i) {
  L: do {
    do {
      if (i != null) continue L;
    } while (g(i));
    break;
  } while (h(i));
}
bool g(int j) => true;
bool h(int k) => true;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is promoted at the time of the call to h.
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j, because i is not promoted at the time
    // of the call to g.
    assertEdge(iNode, jNode, hard: false);
  }

  test_continue_unlabeled() async {
    await analyze('''
void f(int i) {
  do {
    if (i != null) continue;
    h(i);
    break;
  } while (g(i));
}
bool g(int j) => true;
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to j because i is promoted at the time of the call to g.
    assertNoEdge(iNode, jNode);
    // But there is an edge from i to j, because i is not promoted at the time
    // of the call to h.
    assertEdge(iNode, kNode, hard: false);
  }

  test_do_break_target() async {
    await analyze('''
void f(int i) {
  L: do {
    do {
      if (i != null) break L;
      if (b()) break;
    } while (true);
    g(i);
  } while (true);
  h(i);
}
bool b() => true;
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is promoted at the time of the call to h.
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j, because i is not promoted at the time
    // of the call to g.
    assertEdge(iNode, jNode, hard: false);
  }

  test_do_cancels_promotions_for_assignments_in_body() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  if (j == null) return;
  do {
    i.isEven;
    j.isEven;
    j = null;
  } while (true);
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never because its promotion was cancelled.
    assertEdge(jNode, never, hard: false);
  }

  test_do_cancels_promotions_for_assignments_in_condition() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  if (j == null) return;
  do {} while (i.isEven && j.isEven && g(j = null));
}
bool g(int k) => true;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never because its promotion was cancelled.
    assertEdge(jNode, never, hard: false);
  }

  test_do_continue_target() async {
    await analyze('''
void f(int i) {
  L: do {
    do {
      if (i != null) continue L;
      g(i);
    } while (true);
  } while (h(i));
}
void g(int j) {}
bool h(int k) => true;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is promoted at the time of the call to h.
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j, because i is not promoted at the time
    // of the call to g.
    assertEdge(iNode, jNode, hard: false);
  }

  test_field_initializer() async {
    await analyze('''
bool b1 = true;
bool b2 = true;
class C {
  bool b = b1 || b2;
}
''');
    // No assertions; we just want to verify that the presence of `||` inside a
    // field doesn't cause flow analysis to crash.
  }

  test_for_break_target() async {
    await analyze('''
void f(int i) {
  L: for (;;) {
    for (;;) {
      if (i != null) break L;
      if (b()) break;
    }
    g(i);
  }
  h(i);
}
bool b() => true;
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is promoted at the time of the call to h.
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j, because i is not promoted at the time
    // of the call to g.
    assertEdge(iNode, jNode, hard: false);
  }

  test_for_cancels_promotions_for_assignments_in_body() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  if (j == null) return;
  for (;;) {
    i.isEven;
    j.isEven;
    j = null;
  }
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never because its promotion was cancelled.
    assertEdge(jNode, never, hard: false);
  }

  test_for_cancels_promotions_for_assignments_in_updaters() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  if (j == null) return;
  for (;; j = null) {
    i.isEven;
    j.isEven;
  }
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never because its promotion was cancelled.
    assertEdge(jNode, never, hard: false);
  }

  test_for_collection_cancels_promotions_for_assignments_in_body() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  if (j == null) return;
  <Object>[for (;;) <Object>[i.isEven, j.isEven, (j = null)]];
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never because its promotion was cancelled.
    assertEdge(jNode, never, hard: false);
  }

  test_for_collection_cancels_promotions_for_assignments_in_updaters() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  if (j == null) return;
  <Object>[for (;; j = null) <Object>[i.isEven, j.isEven]];
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never because its promotion was cancelled.
    assertEdge(jNode, never, hard: false);
  }

  test_for_collection_preserves_promotions_for_assignments_in_initializer() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  <Object>[for(var v = h(i.isEven && j.isEven && g(i = null));;) null];
}
bool g(int k) => true;
int h(bool b) => 0;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because it is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never.
    assertEdge(jNode, never, hard: false);
  }

  test_for_continue_target() async {
    await analyze('''
void f(int i) {
  L: for (; b(); h(i)) {
    for (; b(); g(i)) {
      if (i != null) continue L;
    }
    return;
  }
}
bool b() => true;
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is promoted at the time of the call to h.
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j, because i is not promoted at the time
    // of the call to g.
    assertEdge(iNode, jNode, hard: false);
  }

  test_for_each_cancels_promotions_for_assignments_in_body() async {
    await analyze('''
void f(int i, int j, Iterable<Object> x) {
  if (i == null) return;
  if (j == null) return;
  for (var v in x) {
    i.isEven;
    j.isEven;
    j = null;
  }
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never because its promotion was cancelled.
    assertEdge(jNode, never, hard: false);
  }

  test_for_each_collection_cancels_promotions_for_assignments_in_body() async {
    await analyze('''
void f(int i, int j, Iterable<Object> x) {
  if (i == null) return;
  if (j == null) return;
  <Object>[for (var v in x) <Object>[i.isEven, j.isEven, (j = null)]];
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never because its promotion was cancelled.
    assertEdge(jNode, never, hard: false);
  }

  test_for_each_collection_preserves_promotions_for_assignments_in_iterable() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  <Object>[for(var v in h(i.isEven && j.isEven && g(i = null))) null];
}
bool g(int k) => true;
Iterable<Object> h(bool b) => <Object>[];
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because it is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never.
    assertEdge(jNode, never, hard: false);
  }

  test_for_each_preserves_promotions_for_assignments_in_iterable() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  for(var v in h(i.isEven && j.isEven && g(i = null))) {}
}
bool g(int k) => true;
Iterable<Object> h(bool b) => <Object>[];
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because it is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never.
    assertEdge(jNode, never, hard: false);
  }

  test_for_preserves_promotions_for_assignments_in_initializer() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  for(var v = h(i.isEven && j.isEven && g(i = null));;) {}
}
bool g(int k) => true;
int h(bool b) => 0;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because it is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never.
    assertEdge(jNode, never, hard: false);
  }

  test_functionDeclaration() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  print(i.isEven);
  print(j.isEven);
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: false);
  }

  test_functionDeclaration_expression_body() async {
    await analyze('''
bool f(int i) => i == null || i.isEven;
bool g(int j) => j.isEven;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: true);
  }

  test_functionDeclaration_resets_unconditional_control_flow() async {
    await analyze('''
void f(bool b, int i, int j) {
  assert(i != null);
  if (b) return;
  assert(j != null);
}
void g(int k) {
  assert(k != null);
}
''');
    assertEdge(decoratedTypeAnnotation('int i').node, never, hard: true);
    assertNoEdge(always, decoratedTypeAnnotation('int j').node);
    assertEdge(decoratedTypeAnnotation('int k').node, never, hard: true);
  }

  test_functionExpression_parameters() async {
    await analyze('''
void f() {
  var g = (int i, int j) {
    if (i == null) return;
    print(i.isEven);
    print(j.isEven);
  };
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: false);
  }

  test_if() async {
    await analyze('''
void f(int i) {
  if (i == null) {
    g(i);
  } else {
    h(i);
  }
}
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is known to be non-nullable at the site of
    // the call to h()
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j
    assertEdge(iNode, jNode, hard: false, guards: [iNode]);
  }

  test_if_without_else() async {
    await analyze('''
void f(int i) {
  if (i == null) {
    g(i);
    return;
  }
  h(i);
}
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is known to be non-nullable at the site of
    // the call to h()
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j
    assertEdge(iNode, jNode, hard: false, guards: [iNode]);
  }

  test_ifNull() async {
    await analyze('''
void f(int i, int x) {
  x ?? (i == null ? throw 'foo' : g(i));
  h(i);
}
int g(int j) => 0;
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to j because i's type is promoted to non-nullable
    assertNoEdge(iNode, jNode);
    // But there is an edge from i to k, because the RHS of the `??` isn't
    // guaranteed to execute.
    assertEdge(iNode, kNode, hard: true);
  }

  test_local_function_parameters() async {
    await analyze('''
void f() {
  void g(int i, int j) {
    if (i == null) return;
    print(i.isEven);
    print(j.isEven);
  }
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: false);
  }

  test_not() async {
    await analyze('''
void f(int i) {
  if (!(i == null)) {
    h(i);
  } else {
    g(i);
  }
}
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is known to be non-nullable at the site of
    // the call to h()
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j
    assertEdge(iNode, jNode, hard: false);
  }

  test_rethrow() async {
    await analyze('''
void f(int i, int j) {
  try {
    g();
  } catch (_) {
    if (i == null) rethrow;
    print(i.isEven);
    print(j.isEven);
  }
}
void g() {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: false);
  }

  test_return() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  print(i.isEven);
  print(j.isEven);
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: false);
  }

  test_switch_break_target() async {
    await analyze('''
void f(int i, int x, int y) {
  L: switch (x) {
    default:
      switch (y) {
        default:
          if (i != null) break L;
          if (b()) break;
          return;
      }
      g(i);
      return;
  }
  h(i);
}
bool b() => true;
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is promoted at the time of the call to h.
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j, because i is not promoted at the time
    // of the call to g.
    assertEdge(iNode, jNode, hard: false);
  }

  test_switch_cancels_promotions_for_labeled_cases() async {
    await analyze('''
void f(int i, int x, bool b) {
  if (i == null) return;
  switch (x) {
    L:
    case 1:
      g(i);
      break;
    case 2:
      h(i);
      i = null;
      if (b) continue L;
      break;
  }
}
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i's type is promoted to non-nullable at the
    // time of the call to h.
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j.
    assertEdge(iNode, jNode, hard: false);
  }

  test_switch_default() async {
    await analyze('''
void f(int i, int j, int x, int y) {
  if (i == null) {
    switch (x) {
      default: return;
    }
  }
  if (j == null) {
    switch (y) {
      case 0: return;
    }
  }
  i.isEven;
  j.isEven;
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because the switch statement is guaranteed to
    // complete by returning, so i is promoted to non-nullable.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never, because the switch statement is not
    // guaranteed to complete by returning, so j is not promoted.
    assertEdge(jNode, never, hard: false);
  }

  test_throw() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) throw 'foo';
  print(i.isEven);
  print(j.isEven);
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to `never` because i's type is promoted to non-nullable
    assertNoEdge(iNode, never);
    // But there is an edge from j to `never`.
    assertEdge(jNode, never, hard: true);
  }

  test_topLevelVar_initializer() async {
    await analyze('''
bool b1 = true;
bool b2 = true;
bool b3 = b1 || b2;
''');
    // No assertions; we just want to verify that the presence of `||` inside a
    // top level variable doesn't cause flow analysis to crash.
  }

  test_while_break_target() async {
    await analyze('''
void f(int i) {
  L: while (true) {
    while (true) {
      if (i != null) break L;
      if (b()) break;
    }
    g(i);
  }
  h(i);
}
bool b() => true;
void g(int j) {}
void h(int k) {}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    var kNode = decoratedTypeAnnotation('int k').node;
    // No edge from i to k because i is promoted at the time of the call to h.
    assertNoEdge(iNode, kNode);
    // But there is an edge from i to j, because i is not promoted at the time
    // of the call to g.
    assertEdge(iNode, jNode, hard: false);
  }

  test_while_cancels_promotions_for_assignments_in_body() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  if (j == null) return;
  while (true) {
    i.isEven;
    j.isEven;
    j = null;
  }
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never because its promotion was cancelled.
    assertEdge(jNode, never, hard: false);
  }

  test_while_cancels_promotions_for_assignments_in_condition() async {
    await analyze('''
void f(int i, int j) {
  if (i == null) return;
  if (j == null) return;
  while (i.isEven && j.isEven && g(j = null)) {}
}
bool g(int k) => true;
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never because its promotion was cancelled.
    assertEdge(jNode, never, hard: false);
  }

  test_while_promotes() async {
    await analyze('''
void f(int i, int j) {
  while (i != null) {
    i.isEven;
    j.isEven;
  }
}
''');
    var iNode = decoratedTypeAnnotation('int i').node;
    var jNode = decoratedTypeAnnotation('int j').node;
    // No edge from i to never because is is promoted.
    assertNoEdge(iNode, never);
    // But there is an edge from j to never.
    assertEdge(jNode, never, hard: false);
  }
}
