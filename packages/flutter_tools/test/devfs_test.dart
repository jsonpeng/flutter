// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_tools/src/asset.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/devfs.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/vmservice.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'src/common.dart';
import 'src/context.dart';
import 'src/mocks.dart';

void main() {
  final String filePath = path.join('bar', 'foo.txt');
  final String filePath2 = path.join('foo', 'bar.txt');
  Directory tempDir;
  String basePath;
  DevFS devFS;
  final AssetBundle assetBundle = new AssetBundle();

  group('DevFSContent', () {
    test('bytes', () {
      DevFSByteContent content = new DevFSByteContent(<int>[4, 5, 6]);
      expect(content.bytes, orderedEquals(<int>[4, 5, 6]));
      expect(content.isModified, isTrue);
      expect(content.isModified, isFalse);
      content.bytes = <int>[7, 8, 9, 2];
      expect(content.bytes, orderedEquals(<int>[7, 8, 9, 2]));
      expect(content.isModified, isTrue);
      expect(content.isModified, isFalse);
    });
    test('string', () {
      DevFSStringContent content = new DevFSStringContent('some string');
      expect(content.string, 'some string');
      expect(content.bytes, orderedEquals(UTF8.encode('some string')));
      expect(content.isModified, isTrue);
      expect(content.isModified, isFalse);
      content.string = 'another string';
      expect(content.string, 'another string');
      expect(content.bytes, orderedEquals(UTF8.encode('another string')));
      expect(content.isModified, isTrue);
      expect(content.isModified, isFalse);
      content.bytes = UTF8.encode('foo bar');
      expect(content.string, 'foo bar');
      expect(content.bytes, orderedEquals(UTF8.encode('foo bar')));
      expect(content.isModified, isTrue);
      expect(content.isModified, isFalse);
    });
  });

  group('devfs local', () {
    MockDevFSOperations devFSOperations = new MockDevFSOperations();

    setUpAll(() {
      tempDir = _newTempDir();
      basePath = tempDir.path;
    });
    tearDownAll(_cleanupTempDirs);

    testUsingContext('create dev file system', () async {
      // simulate workspace
      File file = fs.file(path.join(basePath, filePath));
      await file.parent.create(recursive: true);
      file.writeAsBytesSync(<int>[1, 2, 3]);

      // simulate package
      await _createPackage('somepkg', 'somefile.txt');

      devFS = new DevFS.operations(devFSOperations, 'test', tempDir);
      await devFS.create();
      devFSOperations.expectMessages(<String>['create test']);
      expect(devFS.assetPathsToEvict, isEmpty);

      int bytes = await devFS.update();
      devFSOperations.expectMessages(<String>[
        'writeFile test .packages',
        'writeFile test ${path.join('bar', 'foo.txt')}',
        'writeFile test ${path.join('packages', 'somepkg', 'somefile.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, isEmpty);
      expect(bytes, 31);
    });
    testUsingContext('add new file to local file system', () async {
      File file = fs.file(path.join(basePath, filePath2));
      await file.parent.create(recursive: true);
      file.writeAsBytesSync(<int>[1, 2, 3, 4, 5, 6, 7]);
      int bytes = await devFS.update();
      devFSOperations.expectMessages(<String>[
        'writeFile test ${path.join('foo', 'bar.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, isEmpty);
      expect(bytes, 7);
    });
    testUsingContext('modify existing file on local file system', () async {
      File file = fs.file(path.join(basePath, filePath));
      // Set the last modified time to 5 seconds in the past.
      updateFileModificationTime(file.path, new DateTime.now(), -5);
      int bytes = await devFS.update();
      devFSOperations.expectMessages(<String>[]);
      expect(devFS.assetPathsToEvict, isEmpty);
      expect(bytes, 0);

      await file.writeAsBytes(<int>[1, 2, 3, 4, 5, 6]);
      bytes = await devFS.update();
      devFSOperations.expectMessages(<String>[
        'writeFile test ${path.join('bar', 'foo.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, isEmpty);
      expect(bytes, 6);
    }, skip: io.Platform.isWindows); // TODO(goderbauer): enable when updateFileModificationTime is ported to Windows
    testUsingContext('delete a file from the local file system', () async {
      File file = fs.file(path.join(basePath, filePath));
      await file.delete();
      int bytes = await devFS.update();
      devFSOperations.expectMessages(<String>[
        'deleteFile test ${path.join('bar', 'foo.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, isEmpty);
      expect(bytes, 0);
    });
    testUsingContext('add new package', () async {
      await _createPackage('newpkg', 'anotherfile.txt');
      int bytes = await devFS.update();
      devFSOperations.expectMessages(<String>[
        'writeFile test .packages',
        'writeFile test ${path.join('packages', 'newpkg', 'anotherfile.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, isEmpty);
      expect(bytes, 51);
    });
    testUsingContext('add an asset bundle', () async {
      assetBundle.entries['a.txt'] = new DevFSStringContent('abc');
      int bytes = await devFS.update(bundle: assetBundle, bundleDirty: true);
      devFSOperations.expectMessages(<String>[
        'writeFile test ${_inAssetBuildDirectory('a.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, unorderedMatches(<String>['a.txt']));
      devFS.assetPathsToEvict.clear();
      expect(bytes, 3);
    });
    testUsingContext('add a file to the asset bundle - bundleDirty', () async {
      assetBundle.entries['b.txt'] = new DevFSStringContent('abcd');
      int bytes = await devFS.update(bundle: assetBundle, bundleDirty: true);
      // Expect entire asset bundle written because bundleDirty is true
      devFSOperations.expectMessages(<String>[
        'writeFile test ${_inAssetBuildDirectory('a.txt')}',
        'writeFile test ${_inAssetBuildDirectory('b.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, unorderedMatches(<String>[
        'a.txt', 'b.txt']));
      devFS.assetPathsToEvict.clear();
      expect(bytes, 7);
    });
    testUsingContext('add a file to the asset bundle', () async {
      assetBundle.entries['c.txt'] = new DevFSStringContent('12');
      int bytes = await devFS.update(bundle: assetBundle);
      devFSOperations.expectMessages(<String>[
        'writeFile test ${_inAssetBuildDirectory('c.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, unorderedMatches(<String>[
        'c.txt']));
      devFS.assetPathsToEvict.clear();
      expect(bytes, 2);
    });
    testUsingContext('delete a file from the asset bundle', () async {
      assetBundle.entries.remove('c.txt');
      int bytes = await devFS.update(bundle: assetBundle);
      devFSOperations.expectMessages(<String>[
        'deleteFile test ${_inAssetBuildDirectory('c.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, unorderedMatches(<String>['c.txt']));
      devFS.assetPathsToEvict.clear();
      expect(bytes, 0);
    });
    testUsingContext('delete all files from the asset bundle', () async {
      assetBundle.entries.clear();
      int bytes = await devFS.update(bundle: assetBundle, bundleDirty: true);
      devFSOperations.expectMessages(<String>[
        'deleteFile test ${_inAssetBuildDirectory('a.txt')}',
        'deleteFile test ${_inAssetBuildDirectory('b.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, unorderedMatches(<String>[
        'a.txt', 'b.txt'
      ]));
      devFS.assetPathsToEvict.clear();
      expect(bytes, 0);
    });
    testUsingContext('delete dev file system', () async {
      await devFS.destroy();
      devFSOperations.expectMessages(<String>['destroy test']);
      expect(devFS.assetPathsToEvict, isEmpty);
    });
  });

  group('devfs remote', () {
    MockVMService vmService;

    setUpAll(() async {
      tempDir = _newTempDir();
      basePath = tempDir.path;
      vmService = new MockVMService();
      await vmService.setUp();
    });
    tearDownAll(() async {
      await vmService.tearDown();
      _cleanupTempDirs();
    });

    testUsingContext('create dev file system', () async {
      // simulate workspace
      File file = fs.file(path.join(basePath, filePath));
      await file.parent.create(recursive: true);
      file.writeAsBytesSync(<int>[1, 2, 3]);

      // simulate package
      await _createPackage('somepkg', 'somefile.txt');

      devFS = new DevFS(vmService, 'test', tempDir);
      await devFS.create();
      vmService.expectMessages(<String>['create test']);
      expect(devFS.assetPathsToEvict, isEmpty);

      int bytes = await devFS.update();
      vmService.expectMessages(<String>[
        'writeFile test .packages',
        'writeFile test ${path.join('bar', 'foo.txt')}',
        'writeFile test ${path.join('packages', 'somepkg', 'somefile.txt')}',
      ]);
      expect(devFS.assetPathsToEvict, isEmpty);
      expect(bytes, 31);
    }, timeout: new Timeout(new Duration(seconds: 5)));

    testUsingContext('delete dev file system', () async {
      await devFS.destroy();
      vmService.expectMessages(<String>['_deleteDevFS {fsName: test}']);
      expect(devFS.assetPathsToEvict, isEmpty);
    });
  });
}

class MockVMService extends BasicMock implements VMService {
  Uri _httpAddress;
  HttpServer _server;
  MockVM _vm;

  MockVMService() {
    _vm = new MockVM(this);
  }

  @override
  Uri get httpAddress => _httpAddress;

  @override
  VM get vm => _vm;

  Future<Null> setUp() async {
    _server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 0);
    _httpAddress = Uri.parse('http://127.0.0.1:${_server.port}');
    _server.listen((HttpRequest request) {
      String fsName = request.headers.value('dev_fs_name');
      String devicePath = UTF8.decode(BASE64.decode(request.headers.value('dev_fs_path_b64')));
      messages.add('writeFile $fsName $devicePath');
      request.drain<List<int>>().then<Null>((List<int> value) {
        request.response
          ..write('Got it')
          ..close();
      });
    });
  }

  Future<Null> tearDown() async {
    await _server.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockVM implements VM {
  final MockVMService _service;
  final Uri _baseUri = Uri.parse('file:///tmp/devfs/test');

  MockVM(this._service);

  @override
  Future<Map<String, dynamic>> createDevFS(String fsName) async {
    _service.messages.add('create $fsName');
    return <String, dynamic>{'uri': '$_baseUri'};
  }

  @override
  Future<Map<String, dynamic>> invokeRpcRaw(String method, {
    Map<String, dynamic> params: const <String, dynamic>{},
    Duration timeout,
    bool timeoutFatal: true,
  }) async {
    _service.messages.add('$method $params');
    return <String, dynamic>{'success': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}


final List<Directory> _tempDirs = <Directory>[];
final Map <String, Directory> _packages = <String, Directory>{};

Directory _newTempDir() {
  Directory tempDir = fs.systemTempDirectory.createTempSync('devfs${_tempDirs.length}');
  _tempDirs.add(tempDir);
  return tempDir;
}

void _cleanupTempDirs() {
  while (_tempDirs.length > 0) {
    _tempDirs.removeLast().deleteSync(recursive: true);
  }
}

Future<Null> _createPackage(String pkgName, String pkgFileName) async {
  final Directory pkgTempDir = _newTempDir();
  File pkgFile = fs.file(path.join(pkgTempDir.path, pkgName, 'lib', pkgFileName));
  await pkgFile.parent.create(recursive: true);
  pkgFile.writeAsBytesSync(<int>[11, 12, 13]);
  _packages[pkgName] = pkgTempDir;
  StringBuffer sb = new StringBuffer();
  _packages.forEach((String pkgName, Directory pkgTempDir) {
    Uri pkgPath = path.toUri(path.join(pkgTempDir.path, pkgName, 'lib'));
    sb.writeln('$pkgName:$pkgPath');
  });
  fs.file(path.join(_tempDirs[0].path, '.packages')).writeAsStringSync(sb.toString());
}

String _inAssetBuildDirectory(String filename) => path.join(getAssetBuildDirectory(), filename);