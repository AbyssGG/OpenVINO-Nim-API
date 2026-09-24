# SPDX-License-Identifier: Apache-2.0

## SHA-256 (FIPS 180-4), written out in full because nothing in the Nim
## standard library provides it.
##
## `std/sha1` exists but SHA-1 is not what the fixture documentation records,
## and the `checksums` package that carries SHA-256 is not bundled with a Nim
## installation, so depending on it would add a download to `nimble lint` for
## the sake of one hash. This file is about a hundred lines and has published
## test vectors, so writing it costs less than the dependency.
##
## Development tool only. It is not part of the published package surface, is
## not written for speed, and must not be used for anything security-bearing:
## it exists so that a documented fixture checksum can be re-derived and
## therefore cannot quietly become wrong.

import std/strutils

type
  Sha256Digest* = array[32, byte]
    ## A raw 32-byte digest. Call `toHex` for the documented spelling.

const
  roundConstants: array[64, uint32] = [
    0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32,
    0x3956c25b'u32, 0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32,
    0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32,
    0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32,
    0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32,
    0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
    0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32,
    0xc6e00bf3'u32, 0xd5a79147'u32, 0x06ca6351'u32, 0x14292967'u32,
    0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32,
    0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
    0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32,
    0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
    0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32,
    0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32, 0x682e6ff3'u32,
    0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
    0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32]
    ## The 64 round constants, the first 32 bits of the fractional parts of
    ## the cube roots of the first 64 primes.

  initialState: array[8, uint32] = [
    0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32,
    0x510e527f'u32, 0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32]
    ## The initial hash value, from the square roots of the first 8 primes.

  blockSize = 64
    ## Bytes per compression block.

func rotateRight(value: uint32, bits: int): uint32 =
  ## Rotates `value` right by `bits`, which must be in 1 .. 31.
  ##
  ## The bounds matter: a shift of 0 or 32 is undefined in C, and Nim lowers
  ## `shl` to a C shift. Every call below uses a constant in range.
  (value shr bits) or (value shl (32 - bits))

func beWord(data: openArray[byte], offset: int): uint32 =
  ## Reads four bytes at `offset` as a big-endian word, the byte order the
  ## specification uses throughout.
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

func padded(data: openArray[byte]): seq[byte] =
  ## Returns `data` with the specification's padding appended: a single set
  ## bit, then zeroes, then the original length in bits as a big-endian 64-bit
  ## value, so that the result is a whole number of blocks.
  ##
  ## Padding is what makes the length part of the digest, which is why a
  ## message and that message followed by zeroes hash differently.
  let bitLength = uint64(data.len) * 8
  result = newSeqOfCap[byte](data.len + blockSize)
  for value in data:
    result.add(value)
  result.add(0x80'u8)
  while result.len mod blockSize != blockSize - 8:
    result.add(0'u8)
  for shift in countdown(7, 0):
    result.add(byte((bitLength shr (shift * 8)) and 0xff))

func sha256*(data: openArray[byte]): Sha256Digest =
  ## Returns the SHA-256 digest of `data`.
  var state = initialState
  let message = padded(data)

  var offset = 0
  while offset < message.len:
    var schedule: array[64, uint32]
    for index in 0 .. 15:
      schedule[index] = beWord(message, offset + index * 4)
    for index in 16 .. 63:
      let
        left = schedule[index - 15]
        right = schedule[index - 2]
        sigma0 = rotateRight(left, 7) xor rotateRight(left, 18) xor
          (left shr 3)
        sigma1 = rotateRight(right, 17) xor rotateRight(right, 19) xor
          (right shr 10)
      schedule[index] = schedule[index - 16] + sigma0 +
        schedule[index - 7] + sigma1

    var working = state
    for index in 0 .. 63:
      let
        bigSigma1 = rotateRight(working[4], 6) xor
          rotateRight(working[4], 11) xor rotateRight(working[4], 25)
        choice = (working[4] and working[5]) xor
          ((not working[4]) and working[6])
        temp1 = working[7] + bigSigma1 + choice + roundConstants[index] +
          schedule[index]
        bigSigma0 = rotateRight(working[0], 2) xor
          rotateRight(working[0], 13) xor rotateRight(working[0], 22)
        majority = (working[0] and working[1]) xor
          (working[0] and working[2]) xor (working[1] and working[2])
        temp2 = bigSigma0 + majority
      working[7] = working[6]
      working[6] = working[5]
      working[5] = working[4]
      working[4] = working[3] + temp1
      working[3] = working[2]
      working[2] = working[1]
      working[1] = working[0]
      working[0] = temp1 + temp2

    for index in 0 .. 7:
      state[index] = state[index] + working[index]
    offset += blockSize

  for index in 0 .. 7:
    let word = state[index]
    result[index * 4] = byte(word shr 24)
    result[index * 4 + 1] = byte((word shr 16) and 0xff)
    result[index * 4 + 2] = byte((word shr 8) and 0xff)
    result[index * 4 + 3] = byte(word and 0xff)

func toHex*(digest: Sha256Digest): string =
  ## Returns the digest as 64 lowercase hexadecimal characters, the spelling
  ## used in documentation and by `sha256sum`.
  result = newStringOfCap(64)
  for value in digest:
    result.add(toHex(int(value), 2).toLowerAscii())

func sha256Hex*(data: string): string =
  ## Convenience wrapper: hashes the bytes of `data` and returns hexadecimal.
  ##
  ## Takes a `string` because that is what `readFile` returns; the contents are
  ## treated as bytes, not as text, so encoding never enters into it.
  sha256(toOpenArrayByte(data, 0, data.high)).toHex()
