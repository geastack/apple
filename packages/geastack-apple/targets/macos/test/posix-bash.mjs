// The bash the macOS build tests run their shell fixtures in. macOS and Linux
// have /bin/bash. Windows has nothing there, and the `bash` on its PATH is
// usually System32's bash.exe -- the WSL launcher, which would run a fixture in
// a Linux distribution instead of on this host. Git for Windows ships the bash
// every Windows checkout already has: it is found from the git on PATH or its
// standard install directory, and GEA_BASH overrides both, as in the release
// suite (compiler/scripts/host-shell.mjs).
import { existsSync } from 'node:fs'
import { delimiter, dirname, join } from 'node:path'

function gitForWindowsBash() {
  const roots = (process.env.PATH ?? '')
    .split(delimiter)
    .filter((directory) => directory && existsSync(join(directory, 'git.exe')))
    // git.exe sits in <Git>\cmd, <Git>\bin or <Git>\mingw64\bin.
    .flatMap((directory) => [dirname(directory), dirname(dirname(directory))])
  for (const programs of [process.env.ProgramFiles, process.env.ProgramW6432, 'C:\\Program Files'].filter(Boolean)) {
    roots.push(join(programs, 'Git'))
  }
  // bin\bash.exe, not usr\bin\bash.exe: the launcher puts Git's /usr/bin tools on PATH.
  return roots.map((root) => join(root, 'bin', 'bash.exe')).find((candidate) => existsSync(candidate))
}

export const posixBash = process.platform === 'win32' ? process.env.GEA_BASH || gitForWindowsBash() || 'bash' : '/bin/bash'
