/* SQLite runs off the UI thread; callers terminate queries after 4 seconds. */
importScripts('vendor/sql-wasm.js');
let dbPromise;
const safeFunctions=new Set(['sum','avg','count','min','max','round','substr','substring','strftime','date','coalesce','ifnull','nullif','lower','upper','length','abs','cast','trim','replace']);
function validateSQL(sql){
 if(typeof sql!=='string'||sql.length>12000)throw Error('Please enter a SELECT query under 12,000 characters.');
 const clean=sql.replace(/'(?:''|[^'])*'/g,"''").replace(/--[^\n]*/g,'').replace(/\/\*[\s\S]*?\*\//g,'').trim().replace(/;\s*$/,'');
 if(!/^(SELECT|WITH)\b/i.test(clean)||clean.includes(';'))throw Error('Only one read-only SELECT statement is allowed.');
 if(/\b(insert|update|delete|drop|alter|create|attach|detach|pragma|vacuum|reindex|replace|analyze|recursive|load_extension|writefile|readfile|sqlite_master|sqlite_schema|sqlite_temp_master)\b/i.test(clean))throw Error('This workspace accepts read-only analytical SELECT queries only.');
 for(const m of clean.matchAll(/\b([a-z_][a-z_0-9]*)\s*\(/gi)){if(!safeFunctions.has(m[1].toLowerCase())&&!['as','in','over'].includes(m[1].toLowerCase()))throw Error('Unsupported function or CTE syntax. Try a simple SELECT with standard aggregates.');}
 return sql.trim().replace(/;\s*$/,'');
}
async function database(){if(!dbPromise)dbPromise=(async()=>{const SQL=await initSqlJs({locateFile:f=>'vendor/'+f});const payload=await fetch('dataset.json').then(r=>r.json());const db=new SQL.Database();db.run(payload.schema);for(const [table,rows] of Object.entries(payload.data)){let s=db.prepare(`INSERT INTO ${table} VALUES (${rows[0].map(()=>'?').join(',')})`);for(const row of rows)s.run(row);s.free();}db.run('PRAGMA query_only=ON');return db;})();return dbPromise;}
onmessage=async({data})=>{try{const db=await database();const sql=validateSQL(data.sql);const start=performance.now();const statement=db.prepare(sql);const columns=statement.getColumnNames(),rows=[];let truncated=false;try{while(statement.step()){if(rows.length===500){truncated=true;break;}rows.push(statement.get());}}finally{statement.free();}postMessage({id:data.id,columns,rows,truncated,elapsed_ms:Math.round((performance.now()-start)*10)/10,sql});}catch(e){postMessage({id:data.id,error:e.message});}};
