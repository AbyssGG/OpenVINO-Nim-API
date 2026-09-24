# SPDX-License-Identifier: Apache-2.0

## Reports the OpenVINO runtime version and the devices it can see.
##
## The smallest useful program: it proves the runtime loads and that plugins
## were found. Run it first when a deployment is not working, because it
## separates "OpenVINO is not reachable" from "my model is wrong".
##
## Build and run:
##
## ```shell
## nim c -r --path:src examples/list_devices.nim
## ```

import openvino

proc main() =
  # runtimeVersion needs no Core, so it answers even when plugins are missing.
  let version = runtimeVersion()
  echo "OpenVINO runtime"
  echo "  build       : ", version.build
  echo "  description : ", version.description
  if version.parsed:
    echo "  version     : ", version.major, ".", version.minor
  else:
    # Reported rather than guessed. An unparsable build string is not an error.
    echo "  version     : could not be parsed from the build string"
  echo "  matches the version this package pins: ", version.isSupported()
  echo "  pinned baseline: ", TargetOpenVinoVersion

  # Creating a Core is the step that additionally needs plugins.xml, the device
  # plugins and the model frontends from the same runtime directory.
  let core = newCore()
  defer: core.close()

  let devices = core.availableDevices()
  echo ""
  echo "Devices discovered: ", devices.len
  if devices.len == 0:
    echo "  none. The C API library loaded but no plugin did."
    return

  for device in devices:
    echo "  ", device
    # A device need not support every property, so a refusal here is
    # information rather than a failure.
    try:
      echo "    full name: ", core.getProperty(device, "FULL_DEVICE_NAME")
    except OpenVinoError as err:
      echo "    full name: unavailable (", err.statusInfo, ")"

  echo ""
  echo "Nothing above chose a device for you. Compiling requires naming one."

when isMainModule:
  try:
    main()
  except OpenVinoLibraryError as err:
    # The runtime could not be loaded at all. The message already names the
    # platform, the library names tried and how to fix the search path.
    echo "OpenVINO runtime not available."
    echo err.msg
    quit(1)
  except OpenVinoError as err:
    echo "OpenVINO reported a failure during ", err.operation, "."
    echo err.msg
    quit(1)
