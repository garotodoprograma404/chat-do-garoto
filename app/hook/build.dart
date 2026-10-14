// Build hook: compiles the Go core (../core) into a shared library and bundles
// it with the app as a native code asset. Runs automatically on
// `flutter run`, `flutter build` and `flutter test`.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Asset name of the Go core. The generated bindings in
/// lib/src/core_bridge/chatcore.g.dart look the library up by this id.
const _assetName = 'src/core_bridge/chatcore.g.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final coreDir = input.packageRoot.resolve('../core/');
    final libraryName = code.targetOS.dylibFileName('chatcore');
    final library = input.outputDirectory.resolve(libraryName);
    final exports = coreDir.resolve('cmd/chatcore/exports.map').toFilePath();

    final result = await Process.run(
      'go',
      [
        'build',
        '-buildmode=c-shared',
        '-trimpath',
        // No symbol table nor DWARF; a SONAME, which Android uses to identify
        // loaded libraries (Go does not set one by itself); and only the
        // bridge functions exported (exports.map).
        '-ldflags=-s -w '
            '-extldflags=-Wl,-soname,$libraryName,--version-script,$exports',
        '-o',
        library.toFilePath(),
        './cmd/chatcore',
      ],
      workingDirectory: coreDir.toFilePath(),
      environment: {'CGO_ENABLED': '1', 'GOWORK': 'off', ..._goTarget(code)},
    );
    if (result.exitCode != 0) {
      throw Exception(
        'go build of the core failed (is Go installed and on PATH?):\n'
        '${result.stderr}',
      );
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: library,
      ),
    );
    output.dependencies.addAll(await _goInputs(coreDir));
  });
}

/// Go target and C compiler for the platform Flutter is building for.
Map<String, String> _goTarget(CodeConfig code) => switch (code.targetOS) {
  OS.linux => {
    'GOOS': 'linux',
    'GOARCH': _goArch(code.targetArchitecture),
    if (code.cCompiler case final cc?) 'CC': cc.compiler.toFilePath(),
  },
  OS.android => {
    'GOOS': 'android',
    'GOARCH': _goArch(code.targetArchitecture),
    if (code.targetArchitecture == Architecture.arm) 'GOARM': '7',
    'CC': _androidClang(code),
  },
  _ => throw UnsupportedError(
    'Building the Go core for ${code.targetOS} is not supported yet '
    '(desktops other than Linux come in phase 4).',
  ),
};

String _goArch(Architecture arch) => switch (arch) {
  Architecture.x64 => 'amd64',
  Architecture.arm64 => 'arm64',
  Architecture.arm => 'arm',
  _ => throw UnsupportedError(
    'Unsupported architecture for the Go core: $arch',
  ),
};

/// The NDK clang wrapper for the target ABI and minimum API level (for
/// example aarch64-linux-android24-clang). It lives next to the NDK clang that
/// Flutter provides in [CodeConfig.cCompiler].
String _androidClang(CodeConfig code) {
  final clang = code.cCompiler?.compiler;
  if (clang == null) {
    throw StateError(
      'No NDK C compiler for the Android build (is the NDK installed?)',
    );
  }
  final triple = switch (code.targetArchitecture) {
    Architecture.arm64 => 'aarch64-linux-android',
    Architecture.arm => 'armv7a-linux-androideabi',
    Architecture.x64 => 'x86_64-linux-android',
    final arch => throw UnsupportedError(
      'Unsupported Android architecture for the Go core: $arch',
    ),
  };
  final wrapper = '$triple${code.android.targetNdkApi}-clang';
  return clang.resolve(wrapper).toFilePath();
}

/// Every directory under core/ (so new files trigger a rebuild) plus the files
/// that affect the build.
Future<List<Uri>> _goInputs(Uri coreDir) async {
  final root = Directory.fromUri(coreDir);
  final inputs = <Uri>[root.uri];
  await for (final entity in root.list(recursive: true)) {
    final path = entity.path;
    if (entity is Directory) {
      inputs.add(entity.uri);
    } else if (path.endsWith('.go') && !path.endsWith('_test.go') ||
        path.endsWith('.h') ||
        path.endsWith('.c') ||
        path.endsWith('.map') ||
        path.endsWith('go.mod') ||
        path.endsWith('go.sum')) {
      inputs.add(entity.uri);
    }
  }
  return inputs;
}
