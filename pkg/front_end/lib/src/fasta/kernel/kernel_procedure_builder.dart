// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.kernel_procedure_builder;

import 'package:kernel/ast.dart' show
    Arguments,
    AsyncMarker,
    Constructor,
    DartType,
    DynamicType,
    EmptyStatement,
    Expression,
    FunctionNode,
    Initializer,
    Library,
    LocalInitializer,
    Member,
    Name,
    NamedExpression,
    Procedure,
    ProcedureKind,
    RedirectingInitializer,
    Statement,
    SuperInitializer,
    TypeParameter,
    VariableDeclaration,
    VariableGet,
    VoidType,
    setParents;

import 'package:kernel/type_algebra.dart' show
    containsTypeVariable,
    substitute;

import '../errors.dart' show
    internalError;


import '../util/relativize.dart' show
    relativizeUri;

import 'kernel_builder.dart' show
    ClassBuilder,
    ConstructorReferenceBuilder,
    FormalParameterBuilder,
    KernelFormalParameterBuilder,
    KernelLibraryBuilder,
    KernelTypeBuilder,
    KernelTypeVariableBuilder,
    MetadataBuilder,
    ProcedureBuilder,
    TypeVariableBuilder,
    memberError;

abstract class KernelFunctionBuilder
    extends ProcedureBuilder<KernelTypeBuilder> {
  FunctionNode function;

  Statement actualBody;

  KernelFunctionBuilder(
      List<MetadataBuilder> metadata,
      int modifiers, KernelTypeBuilder returnType, String name,
      List<TypeVariableBuilder> typeVariables,
      List<FormalParameterBuilder> formals,
      KernelLibraryBuilder compilationUnit, int charOffset)
      : super(metadata, modifiers, returnType, name, typeVariables, formals,
          compilationUnit, charOffset);

  void set body(Statement newBody) {
    if (isAbstract && newBody != null) {
      return internalError("Attempting to set body on abstract method.");
    }
    actualBody = newBody;
    if (function != null) {
      function.body = newBody;
      newBody?.parent = function;
    }
  }

  Statement get body => actualBody ??= new EmptyStatement();

  FunctionNode buildFunction() {
    assert(function == null);
    FunctionNode result = new FunctionNode(body, asyncMarker: asyncModifier);
    if (typeVariables != null) {
      for (KernelTypeVariableBuilder t in typeVariables) {
        result.typeParameters.add(t.parameter);
      }
      setParents(result.typeParameters, result);
    }
    if (formals != null) {
      for (KernelFormalParameterBuilder formal in formals) {
        VariableDeclaration parameter = formal.build();
        if (formal.isNamed) {
          result.namedParameters.add(parameter);
        } else {
          result.positionalParameters.add(parameter);
        }
        parameter.parent = result;
        if (formal.isRequired) {
          result.requiredParameterCount++;
        }
      }
    }
    if (returnType != null) {
      result.returnType = returnType.build();
    }
    if (!isConstructor && !isInstanceMember && parent is ClassBuilder) {
      List<TypeParameter> typeParameters = parent.target.typeParameters;
      if (typeParameters.isNotEmpty) {
        Map<TypeParameter, DartType> substitution;
        DartType removeTypeVariables(DartType type) {
          if (substitution == null) {
            substitution = <TypeParameter, DartType>{};
            for (TypeParameter parameter in typeParameters) {
              substitution[parameter] = const DynamicType();
            }
          }
          print("Can only use type variables in instance methods.");
          return substitute(type, substitution);
        }
        Set<TypeParameter> set = typeParameters.toSet();
        for (VariableDeclaration parameter in result.positionalParameters) {
          if (containsTypeVariable(parameter.type, set)) {
            parameter.type = removeTypeVariables(parameter.type);
          }
        }
        for (VariableDeclaration parameter in result.namedParameters) {
          if (containsTypeVariable(parameter.type, set)) {
            parameter.type = removeTypeVariables(parameter.type);
          }
        }
        if (containsTypeVariable(result.returnType, set)) {
          result.returnType = removeTypeVariables(result.returnType);
        }
      }
    }
    return function = result;
  }

  Member build(Library library);
}

class KernelProcedureBuilder extends KernelFunctionBuilder {
  final Procedure procedure;

  AsyncMarker actualAsyncModifier;

  final ConstructorReferenceBuilder redirectionTarget;

  KernelProcedureBuilder(
      List<MetadataBuilder> metadata,
      int modifiers, KernelTypeBuilder returnType, String name,
      List<TypeVariableBuilder> typeVariables,
      List<FormalParameterBuilder> formals, this.actualAsyncModifier,
      ProcedureKind kind, KernelLibraryBuilder compilationUnit, int charOffset,
      [this.redirectionTarget])
      : procedure = new Procedure(null, kind, null,
            fileUri: relativizeUri(compilationUnit?.fileUri)),
        super(metadata, modifiers, returnType, name, typeVariables, formals,
            compilationUnit, charOffset);

  ProcedureKind get kind => procedure.kind;

  AsyncMarker get asyncModifier => actualAsyncModifier;

  Statement get body {
    if (actualBody == null && redirectionTarget == null && !isAbstract &&
        !isExternal) {
      actualBody = new EmptyStatement();
    }
    return actualBody;
  }

  void set asyncModifier(AsyncMarker newModifier) {
    actualAsyncModifier = newModifier;
    if (function != null) {
      // No parent, it's an enum.
      function.asyncMarker = actualAsyncModifier;
    }
  }

  Procedure build(Library library) {
    // TODO(ahe): I think we may call this twice on parts. Investigate.
    if (procedure.name == null) {
      procedure.function = buildFunction();
      procedure.function.parent = procedure;
      procedure.isAbstract = isAbstract;
      procedure.isStatic = isStatic;
      procedure.isExternal = isExternal;
      procedure.isConst = isConst;
      procedure.name = new Name(name, library);
    }
    return procedure;
  }

  Procedure get target => procedure;
}

// TODO(ahe): Move this to own file?
class KernelConstructorBuilder extends KernelFunctionBuilder {
  final Constructor constructor = new Constructor(null);

  bool hasMovedSuperInitializer = false;

  SuperInitializer superInitializer;

  RedirectingInitializer redirectingInitializer;

  KernelConstructorBuilder(
      List<MetadataBuilder> metadata,
      int modifiers, KernelTypeBuilder returnType, String name,
      List<TypeVariableBuilder> typeVariables,
      List<FormalParameterBuilder> formals,
      KernelLibraryBuilder compilationUnit, int charOffset)
      : super(metadata, modifiers, returnType, name, typeVariables, formals,
          compilationUnit, charOffset);

  bool get isInstanceMember => false;

  bool get isConstructor => true;

  AsyncMarker get asyncModifier => AsyncMarker.Sync;

  ProcedureKind get kind => null;

  Constructor build(Library library) {
    if (constructor.name == null) {
      constructor.function = buildFunction();
      constructor.function.parent = constructor;
      constructor.isConst = isConst;
      constructor.isExternal = isExternal;
      constructor.name = new Name(name, library);
    }
    return constructor;
  }

  FunctionNode buildFunction() {
    // TODO(ahe): Should complain if another type is explicitly set.
    return super.buildFunction()
        ..returnType = const VoidType();
  }

  Constructor get target => constructor;

  void checkSuperOrThisInitializer(Initializer initializer) {
    if (superInitializer != null || redirectingInitializer != null) {
      memberError(target,
          "Can't have more than one 'super' or 'this' initializer.",
          initializer.fileOffset);
    }
  }

  void addInitializer(Initializer initializer) {
    List<Initializer> initializers = constructor.initializers;
    if (initializer is SuperInitializer) {
      checkSuperOrThisInitializer(initializer);
      superInitializer = initializer;
    } else if (initializer is RedirectingInitializer) {
      checkSuperOrThisInitializer(initializer);
      redirectingInitializer = initializer;
      if (constructor.initializers.isNotEmpty) {
        memberError(target, "'this' initializer must be the only initializer.",
            initializer.fileOffset);
      }
    } else if (redirectingInitializer != null) {
      memberError(target, "'this' initializer must be the only initializer.",
          initializer.fileOffset);
    } else if (superInitializer != null) {
      // If there is a super initializer ([initializer] isn't it), we need to
      // insert [initializer] before the super initializer (thus ensuring that
      // the super initializer is always last).
      assert(superInitializer != initializer);
      assert(initializers.last == superInitializer);
      initializers.removeLast();
      if (!hasMovedSuperInitializer) {
        // To preserve correct evaluation order, the arguments to super call
        // must be evaluated before [initializer]. Once the super initializer
        // has been moved once, the arguments are evaluated in the correct
        // order.
        hasMovedSuperInitializer = true;
        Arguments arguments = superInitializer.arguments;
        List<Expression> positional = arguments.positional;
        for (int i = 0; i < positional.length; i++) {
          VariableDeclaration variable =
              new VariableDeclaration.forValue(positional[i], isFinal: true);
          initializers.add(
              new LocalInitializer(variable)..parent = constructor);
          positional[i] = new VariableGet(variable)..parent = arguments;
        }
        for (NamedExpression named in arguments.named) {
          VariableDeclaration variable =
              new VariableDeclaration.forValue(named.value, isFinal: true);
          named.value = new VariableGet(variable)..parent = named;
          initializers.add(
              new LocalInitializer(variable)..parent = constructor);
        }
      }
      initializers.add(initializer..parent = constructor);
      initializers.add(superInitializer);
      return;
    }
    initializers.add(initializer);
    initializer.parent = constructor;
  }
}
