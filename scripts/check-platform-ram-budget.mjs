// Pure arithmetic examples for Studio RAM planning; no runtime/service access.
import {mkdtempSync,copyFileSync,rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const scratch=mkdtempSync(path.join(tmpdir(),'fios-ram-budget-'));
try {
 const fixture=path.join(scratch,'examples.swift');
 copyFileSync(path.join(root,'platform/studio/Tests/StudioCoreTests/HostRAMBudgetBasic.swift.fixture'),fixture);
 const binary=path.join(scratch,'ram-examples');
 execFileSync('/usr/bin/xcrun',['swiftc','-parse-as-library',path.join(root,'platform/studio/Sources/StudioCore/HostRAMBudget.swift'),fixture,'-o',binary],{stdio:'inherit',timeout:60000});
 execFileSync(binary,[],{stdio:'inherit',timeout:5000});
} finally {rmSync(scratch,{recursive:true,force:true});}
