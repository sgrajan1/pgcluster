let Pool = require('pg').Pool;
let config = require('../config/config.js').pgp;

let pool=new Pool(config);

module.exports.query = function (text, values, callback) {
  console.log('query:', text, values);
  return pool.query(text, values, callback);
};

// the pool also supports checking out a client for
// multiple operations, such as a transaction
module.exports.connect = function (callback) {
  return pool.connect(callback);
};

module.exports.pool = pool;