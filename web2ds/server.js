'use strict';
const http = require('http');
const { handler } = require('./app');
const port = process.env.PORT || 8080;
http.createServer(handler).listen(port, () => console.log('UAM 2DS en http://localhost:' + port));
