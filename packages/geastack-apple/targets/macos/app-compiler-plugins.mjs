import fs from 'node:fs'
import path from 'node:path'
import {createHash} from 'node:crypto'
import {fileURLToPath} from 'node:url'

// Consume the actual CLI apps-inspect record, not a second app registry.
export function appCompilerPlugins(app) {
 if(!app||typeof app.root!=='string'||!path.isAbsolute(app.root))throw Error('Missing absolute app root for compiler plugins')
 const entries=app.compilerPlugins??[]
 if(!Array.isArray(entries))throw Error('Invalid app compilerPlugins')
 const paths=[]
 for(const entry of entries){
  if(typeof entry!=='string'||!entry||/[\x00-\x1f\x7f]/.test(entry)||path.isAbsolute(entry)||entry.split(/[\\/]/).includes('..'))throw Error('Invalid declared app compiler plugin')
  const file=fs.realpathSync(path.resolve(app.root,entry))
  if(!fs.statSync(file).isFile())throw Error('Declared app compiler plugin is not a file: '+file)
  if(!paths.includes(file))paths.push(file)
 }
 const hash=createHash('sha256').update('gea-app-compiler-plugins-v1\0')
 for(const file of paths)hash.update(file).update('\0').update(fs.readFileSync(file)).update('\0')
 return {paths,fingerprint:hash.digest('hex')}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))process.stdout.write(JSON.stringify(appCompilerPlugins(JSON.parse(process.argv[2]))))
