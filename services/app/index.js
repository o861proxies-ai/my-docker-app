const express = require('express')
const fs = require('fs')
const path = require('path')

const app = express()
const PORT = process.env.PORT || 3000
const LOG_DIR = process.env.LOG_DIR || './logs'

// Tạo thư mục log nếu chưa có
fs.mkdirSync(LOG_DIR, { recursive: true })

const logFile = path.join(LOG_DIR, 'app.log')
const logStream = fs.createWriteStream(logFile, { flags: 'a' })

function writeLog(level, message) {
  const line = `[${new Date().toISOString()}] [${level}] ${message}`
  console.log(line)
  logStream.write(line + '\n')
}

// Log mỗi request
app.use((req, res, next) => {
  writeLog('INFO', `${req.method} ${req.url} - ip:${req.ip}`)
  next()
})

// Route chính
app.get('/', (req, res) => {
  res.json({
    message: 'Hello World!',
    service: 'my-docker-app',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development'
  })
})

// Health check
app.get('/health', (req, res) => {
  writeLog('INFO', 'Health check requested')
  res.json({ status: 'ok', uptime: process.uptime() })
})

// Xem 50 dòng log cuối qua API
app.get('/logs/tail', (req, res) => {
  try {
    const content = fs.readFileSync(logFile, 'utf-8')
    const lines = content.trim().split('\n').slice(-50)
    res.json({ lines, total: lines.length })
  } catch {
    res.json({ lines: [], total: 0 })
  }
})

app.listen(PORT, () => {
  writeLog('INFO', `Server started on port ${PORT} | env=${process.env.NODE_ENV || 'development'}`)
})
