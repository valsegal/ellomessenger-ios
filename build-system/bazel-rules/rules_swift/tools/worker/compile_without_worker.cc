// Copyright 2019 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "tools/worker/compile_without_worker.h"

#include <iostream>
#include <string>
#include <vector>

#include "tools/worker/swift_runner.h"

int CompileWithoutWorker(const std::vector<std::string> &args,
                         std::string index_import_path) {
  return SwiftRunner(args, index_import_path)
      .Run(&std::cerr, /*stdout_to_stderr=*/false);
}
