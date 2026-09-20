#!/usr/bin/env node
import childProcess from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const teamIdPattern = /^[A-Z0-9]{10}$/

function run(command, args, input = undefined) {
  const result = childProcess.spawnSync(command, args, {
    encoding: 'utf8',
    input,
    stdio: ['pipe', 'pipe', 'ignore'],
  })
  return result.status === 0 ? result.stdout.trim() : ''
}

function addTeam(teams, id, name, source) {
  if (!teamIdPattern.test(id)) return
  const existing = teams.get(id)
  teams.set(id, {
    id,
    name: existing?.name || name || '',
    sources: [...new Set([...(existing?.sources || []), source])],
  })
}

function readXcodePreferences(teams) {
  const plistPath = path.join(os.homedir(), 'Library/Preferences/com.apple.dt.Xcode.plist')
  if (!fs.existsSync(plistPath)) return ''

  const lastSelected = run('/usr/bin/plutil', [
    '-extract',
    'IDEProvisioningTeamManagerLastSelectedTeamID',
    'raw',
    '-o',
    '-',
    plistPath,
  ])

  const rawTeams = run('/usr/bin/plutil', [
    '-extract',
    'IDEProvisioningTeamByIdentifier',
    'json',
    '-o',
    '-',
    plistPath,
  ])

  if (rawTeams) {
    try {
      const byAccount = JSON.parse(rawTeams)
      for (const accountTeams of Object.values(byAccount)) {
        if (!Array.isArray(accountTeams)) continue
        for (const team of accountTeams) {
          addTeam(teams, team.teamID || '', team.teamName || '', 'Xcode account')
        }
      }
    } catch {
      // Ignore malformed preference data; provisioning profiles may still help.
    }
  }

  return teamIdPattern.test(lastSelected) ? lastSelected : ''
}

function readProvisioningProfiles(teams) {
  const profileDir = path.join(
    os.homedir(),
    'Library/Developer/Xcode/UserData/Provisioning Profiles',
  )
  if (!fs.existsSync(profileDir)) return

  for (const entry of fs.readdirSync(profileDir)) {
    if (!entry.endsWith('.mobileprovision') && !entry.endsWith('.provisionprofile')) continue
    const profilePath = path.join(profileDir, entry)
    const decoded = run('/usr/bin/security', ['cms', '-D', '-i', profilePath])
    if (!decoded) continue
    const id = run('/usr/bin/plutil', ['-extract', 'TeamIdentifier.0', 'raw', '-o', '-', '-'], decoded)
    const name = run('/usr/bin/plutil', ['-extract', 'TeamName', 'raw', '-o', '-', '-'], decoded)
    addTeam(teams, id, name, 'provisioning profile')
  }
}

const teams = new Map()
const lastSelected = readXcodePreferences(teams)
readProvisioningProfiles(teams)

if (lastSelected) {
  console.log(lastSelected)
  process.exit(0)
}

if (teams.size === 1) {
  console.log([...teams.keys()][0])
  process.exit(0)
}

if (teams.size > 1) {
  console.error('Multiple Xcode development teams found:')
  for (const team of teams.values()) {
    const label = team.name ? `${team.id} (${team.name})` : team.id
    console.error(`  ${label}`)
  }
  console.error('Set GEA_IOS_DEVELOPMENT_TEAM to choose one.')
  process.exit(2)
}

process.exit(1)
