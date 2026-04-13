require('dotenv').config();
const http = require('http');
const url = require('url');
const fs = require('fs');
const path = require('path');

const port = 3000;
const callerId = process.env.CALLER_ID || '+918046733542';
const defaultDestination = process.env.DEFAULT_DESTINATION;
const defaultCountryCode = process.env.DEFAULT_COUNTRY_CODE || '91';

// Stores the most recent destination sent by the Flutter app.
let lastDialedNumber = null;

function normalizePhoneNumber(value) {
    if (!value) return '';
    return String(value).replace(/[^\d+]/g, '').trim();
}

function formatToE164(value) {
    const normalized = normalizePhoneNumber(value);
    if (!normalized) return '';
    if (normalized.startsWith('+')) return normalized;
    if (normalized.length === 10) return `+${defaultCountryCode}${normalized}`;
    if (normalized.length === 11 && normalized.startsWith('0')) {
        return `+${defaultCountryCode}${normalized.substring(1)}`;
    }
    return `+${normalized}`;
}

function isSameNumber(a, b) {
    const left = normalizePhoneNumber(a).replace(/^\+/, '');
    const right = normalizePhoneNumber(b).replace(/^\+/, '');
    return left.length > 0 && left === right;
}

const server = http.createServer((req, res) => {
    console.log(`[${new Date().toISOString()}] Request: ${req.method} ${req.url}`);

    if (req.url.startsWith('/client')) {
        const filePath = path.join(__dirname, req.url);

        fs.readFile(filePath, (err, data) => {
            if (err) {
                console.error('File not found:', filePath);
                res.writeHead(404);
                res.end('Not found');
                return;
            }

            if (filePath.endsWith('.html')) {
                res.setHeader('Content-Type', 'text/html');
            } else if (filePath.endsWith('.js')) {
                res.setHeader('Content-Type', 'application/javascript');
            } else if (filePath.endsWith('.css')) {
                res.setHeader('Content-Type', 'text/css');
            } else if (filePath.endsWith('.png')) {
                res.setHeader('Content-Type', 'image/png');
            }

            res.writeHead(200);
            res.end(data);
        });

        return;
    }

    if (req.method === 'POST' && req.url === '/call') {
        let body = '';

        req.on('data', (chunk) => {
            body += chunk.toString();
        });

        req.on('end', () => {
            try {
                const data = JSON.parse(body);
                lastDialedNumber = formatToE164(data.to);

                console.log(`Call requested from Flutter -> ${lastDialedNumber}`);

                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true }));
            } catch (e) {
                console.error('Error parsing request:', e);
                res.writeHead(400);
                res.end('Invalid JSON');
            }
        });

        return;
    }

    const parsedUrl = url.parse(req.url, true);
    if (parsedUrl.pathname === '/hangup') {
        const emptyResponse = `<?xml version="1.0" encoding="UTF-8"?>
<Response></Response>`;
        res.statusCode = 200;
        res.setHeader('Content-Type', 'text/xml');
        res.end(emptyResponse);
        console.log('Hangup callback endpoint hit -> empty XML returned');
        return;
    }

    const isAnswerWebhook =
        parsedUrl.pathname === '/' ||
        parsedUrl.pathname === '/answer';

    if (!isAnswerWebhook) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not found');
        return;
    }

    const respondWithXml = (fields = {}) => {
        const eventName =
            fields.Event ||
            fields.event ||
            fields.CallStatus ||
            fields.callstatus;
        if (
            eventName &&
            String(eventName).toLowerCase().includes('hangup')
        ) {
            const emptyResponse = `<?xml version="1.0" encoding="UTF-8"?>
<Response></Response>`;
            res.statusCode = 200;
            res.setHeader('Content-Type', 'text/xml');
            res.end(emptyResponse);
            console.log('Hangup event received -> returned empty XML response');
            return;
        }

        const query = parsedUrl.query || {};

        let destination =
            lastDialedNumber ||
            fields.Destination ||
            fields.destination ||
            fields.To ||
            fields.to ||
            query.To ||
            query.to ||
            query.Destination ||
            query.destination;

        if (destination && String(destination).startsWith('sip:')) {
            try {
                const match = String(destination).match(/^sip:(.*?)@/);
                if (match && match[1]) {
                    destination = match[1];
                }
            } catch (e) {
                console.error('Error parsing SIP URI:', e);
            }
        }

        destination = formatToE164(destination);

        if (!destination) {
            if (!defaultDestination) {
                console.error('No destination found and DEFAULT_DESTINATION is not configured.');
                res.writeHead(400, { 'Content-Type': 'text/plain' });
                res.end('No destination found. Set DEFAULT_DESTINATION or provide a call destination.');
                return;
            }

            console.log('No destination found, using DEFAULT_DESTINATION from environment');
            destination = formatToE164(defaultDestination);
        }

        if (!callerId) {
            console.error('CALLER_ID is not configured.');
            res.writeHead(500, { 'Content-Type': 'text/plain' });
            res.end('CALLER_ID is not configured. Add it to Vobiz-RTC-demo/.env');
            return;
        }

        if (isSameNumber(destination, callerId)) {
            console.error(`Blocked self-call: callerId ${callerId}, destination ${destination}`);
            res.writeHead(400, { 'Content-Type': 'text/plain' });
            res.end('Destination cannot be same as callerId');
            return;
        }

        const xmlResponse = `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Dial callerId="${callerId}">
        <Number>${destination}</Number>
    </Dial>
</Response>`;

        res.statusCode = 200;
        res.setHeader('Content-Type', 'text/xml');
        res.end(xmlResponse);

        console.log(`XML returned -> callerId: ${callerId}, destination: ${destination}`);
    };

    if (req.method === 'POST') {
        let body = '';
        req.on('data', (chunk) => {
            body += chunk.toString();
        });
        req.on('end', () => {
            let fields = {};
            try {
                fields = Object.fromEntries(new URLSearchParams(body).entries());
            } catch (_) {
                fields = {};
            }
            respondWithXml(fields);
        });
        return;
    }

    respondWithXml();
});

server.listen(port, () => {
    console.log(`
-------------------------------------------------------
  Vobiz Backend running on port ${port}
-------------------------------------------------------
  Frontend (Web UI):
     http://localhost:${port}/client/index.html

  Flutter calls:
     http://<your-lan-ip>:${port}/call

  Vobiz Answer URL:
     https://<your-ngrok-url>/
-------------------------------------------------------
    `);
});
