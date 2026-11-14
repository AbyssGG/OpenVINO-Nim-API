# SPDX-License-Identifier: Apache-2.0

## The single C ABI adapter needed for GenAI's three variadic constructors.
## All other GenAI functions are bound directly through the dynamic loader.

import ../errors
import conversions

{.emit: """
#include <stddef.h>
typedef int (*OpenVinoNimGenAiCreateFn)(const char*, const char*, size_t,
                                       void**, ...);
int openvino_nim_genai_create_bridge(void* address,
                                     char* model,
                                     char* device,
                                     size_t property_pairs,
                                     char** properties,
                                     void* output) {
  OpenVinoNimGenAiCreateFn create = (OpenVinoNimGenAiCreateFn)address;
  switch (property_pairs) {
  case 0: return create(model, device, 0, (void**)output);
  case 1: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1]);
  case 2: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3]);
  case 3: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5]);
  case 4: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7]);
  case 5: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9]);
  case 6: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11]);
  case 7: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11], properties[12], properties[13]);
  case 8: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11], properties[12], properties[13], properties[14], properties[15]);
  case 9: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11], properties[12], properties[13], properties[14], properties[15], properties[16], properties[17]);
  case 10: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11], properties[12], properties[13], properties[14], properties[15], properties[16], properties[17], properties[18], properties[19]);
  case 11: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11], properties[12], properties[13], properties[14], properties[15], properties[16], properties[17], properties[18], properties[19], properties[20], properties[21]);
  case 12: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11], properties[12], properties[13], properties[14], properties[15], properties[16], properties[17], properties[18], properties[19], properties[20], properties[21], properties[22], properties[23]);
  case 13: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11], properties[12], properties[13], properties[14], properties[15], properties[16], properties[17], properties[18], properties[19], properties[20], properties[21], properties[22], properties[23], properties[24], properties[25]);
  case 14: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11], properties[12], properties[13], properties[14], properties[15], properties[16], properties[17], properties[18], properties[19], properties[20], properties[21], properties[22], properties[23], properties[24], properties[25], properties[26], properties[27]);
  case 15: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11], properties[12], properties[13], properties[14], properties[15], properties[16], properties[17], properties[18], properties[19], properties[20], properties[21], properties[22], properties[23], properties[24], properties[25], properties[26], properties[27], properties[28], properties[29]);
  case 16: return create(model, device, property_pairs * 2, (void**)output, properties[0], properties[1], properties[2], properties[3], properties[4], properties[5], properties[6], properties[7], properties[8], properties[9], properties[10], properties[11], properties[12], properties[13], properties[14], properties[15], properties[16], properties[17], properties[18], properties[19], properties[20], properties[21], properties[22], properties[23], properties[24], properties[25], properties[26], properties[27], properties[28], properties[29], properties[30], properties[31]);
  default: return -14;
  }
}
""".}

proc cGenAiCreate(address: pointer; model, device: cstring;
                  propertyPairs: csize_t; properties: ptr cstring;
                  output: pointer): cint
  {.importc: "openvino_nim_genai_create_bridge", cdecl.}

proc createGenAiPipeline*[T](address: pointer; model, device: string;
                             properties: openArray[(string, string)];
                             output: ptr ptr T): cint =
  ## Calls one upstream variadic pipeline constructor without declaring a
  ## C varargs procedure in Nim. Values are passed as the C API requires:
  ## strings, including numeric property values.
  if properties.len > 16:
    raiseArgumentError("GenAI pipeline constructors accept at most 16 " &
      "property pairs through this adapter")
  checkCString(model, "GenAI model path")
  checkCString(device, "GenAI device")
  var rawProperties: seq[cstring] = @[]
  for property in properties:
    checkCString(property[0], "GenAI property key")
    checkCString(property[1], "GenAI property value")
    rawProperties.add(property[0].cstring)
    rawProperties.add(property[1].cstring)
  let rawPointer = if rawProperties.len == 0: nil
                   else: addr rawProperties[0]
  # invariant: a pointer to an opaque GenAI handle slot has the same C ABI as
  # the `void**` output parameter in all three upstream constructors.
  result = cGenAiCreate(address, model.cstring, device.cstring,
                        csize_t(properties.len), rawPointer,
                        cast[pointer](output))
