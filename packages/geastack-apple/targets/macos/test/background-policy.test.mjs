import assert from 'node:assert/strict'
import {execFileSync,spawnSync} from 'node:child_process'
import {mkdirSync} from 'node:fs'
import {fileURLToPath} from 'node:url'

if(process.platform!=='darwin') throw new Error('AppKit policy test requires macOS')
const main=fileURLToPath(new URL('../main',import.meta.url))
const dist=fileURLToPath(new URL('../../../dist',import.meta.url))
mkdirSync(dist,{recursive:true})
const executable=`${dist}/background-policy-test`
execFileSync('clang++',['-std=c++20','-fobjc-arc','-I',main,fileURLToPath(new URL('./background-policy.mm',import.meta.url)),'-framework','AppKit','-o',executable],{stdio:'inherit'})
const base={...process.env}
for(const flag of ['','true','0']){
 const run=spawnSync(executable,[],{env:{...base,GEA_MACOS_BACKGROUND_TEST:flag,GEA_AUDIO_DISABLED:'1'},encoding:'utf8',timeout:10000})
 assert.equal(run.status,78,`malformed mode ${JSON.stringify(flag)} must refuse`)
 assert.match(run.stderr,/must be absent or exactly 1/)
}
const noAudio={...base,GEA_MACOS_BACKGROUND_TEST:'1'};delete noAudio.GEA_AUDIO_DISABLED
const refused=spawnSync(executable,[],{env:noAudio,encoding:'utf8',timeout:10000})
assert.equal(refused.status,78);assert.match(refused.stderr,/GEA_AUDIO_DISABLED=1 is required/)
const accepted=spawnSync(executable,[],{env:{...base,GEA_MACOS_BACKGROUND_TEST:'1',GEA_AUDIO_DISABLED:'1'},encoding:'utf8',timeout:10000})
assert.equal(accepted.status,0,accepted.stderr)
const state=JSON.parse(accepted.stdout.trim())
assert.equal(state.policy,2)
for(const key of ['active','visible','key','main'])assert.equal(state[key],false,key)
console.log(JSON.stringify({scope:'Native AppKit presentation policy',refusals:4,state}))
