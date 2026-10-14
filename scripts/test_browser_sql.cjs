// Test the same SQLite WASM engine and worker query path without a browser.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const initSqlJs=require('../dist/vendor/sql-wasm.js');
let messages=[];
const context={importScripts:()=>{},initSqlJs:()=>initSqlJs({locateFile:f=>require('path').resolve(__dirname,'../dist/vendor',f)}),fetch:async()=>({json:async()=>JSON.parse(fs.readFileSync('dist/dataset.json','utf8'))}),performance,postMessage:msg=>messages.push(msg),console};
vm.createContext(context);vm.runInContext(fs.readFileSync('dist/db-worker.js','utf8'),context);
(async()=>{const catalog=JSON.parse(fs.readFileSync('dist/catalog.json','utf8'));for(const [id,e] of catalog.entries()){await context.onmessage({data:{id,sql:e.sql}});const r=messages.pop();assert(!r.error,r.error);assert(r.rows.length>0,e.id);console.log(e.id+': '+r.rows.length+' rows');}
for(const sql of ['DELETE FROM orders','SELECT 1; DROP TABLE orders','SELECT randomblob(999999999)','PRAGMA query_only=OFF',"SELECT load_extension('x')"]){await context.onmessage({data:{id:99,sql}});assert(messages.pop().error);}
await context.onmessage({data:{id:100,sql:'SELECT * FROM order_items'}});const capped=messages.pop();assert(capped.truncated&&capped.rows.length===500);console.log('Browser SQLite: 8 sample queries, 5 blocked statements, and row cap verified.');})().catch(e=>{console.error(e);process.exit(1);});
