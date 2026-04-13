require('dotenv').config();
const http = require('http');
const { URL } = require('url');
const querystring = require('querystring');
const fs = require('fs');
const path = require('path');

const port = 3000;
const callerId = process.env.CALLER_ID || '';
const sipEndpoint = process.env.SIP_ENDPOINT;
const defaultDestination = process.env.DEFAULT_DESTINATION;
const defaultCountryCode = process.env.DEFAULT_COUNTRY_CODE || '91';

// Stores the most recent outbound destination sent by the Flutter app.
let lastDialedNumber = null;
const registeredPushTokens = new Map();

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

function parseBody(req, body) {
    const contentType = String(req.headers['content-type'] || '').toLowerCase();

    if (contentType.includes('application/json')) {
        if (!body.trim()) {
            return {};
        }

        try {
            return JSON.parse(body);
        } catch (error) {
            throw new Error(`Invalid JSON body: ${error.message}`);
        }
    }

    if (!body.trim()) {
        return {};
    }

    return querystring.parse(body);
}

function sendXml(res, xml) {
    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/xml');
    res.end(xml);
}

function sendText(res, statusCode, message) {
    res.statusCode = statusCode;
    res.setHeader('Content-Type', 'text/plain');
    res.end(message);
}

function maskSecret(value) {
    const text = String(value || '');
    if (text.length <= 8) return '********';
    return `${text.slice(0, 4)}...${text.slice(-4)}`;
}

function redactSensitiveParams(params) {
    const redacted = {};
    for (const [key, value] of Object.entries(params || {})) {
        if (/(password|pass|token|secret)/i.test(key)) {
            redacted[key] = maskSecret(value);
            continue;
        }
        redacted[key] = value;
    }
    return redacted;
}

function escapeXml(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
}

function hasPlaceholder(value) {
    return /<[^>]+>/.test(String(value || ''));
}

function validateCallerId(value) {
    if (!value) {
        return 'Server misconfigured: CALLER_ID environment variable is not set.';
    }

    if (hasPlaceholder(value)) {
        return 'Server misconfigured: CALLER_ID still contains placeholder markers. Use a real number like +918046733542 (no < >).';
    }

    return '';
}

function validateSipEndpoint(value) {
    if (!value) {
        return 'Server misconfigured: SIP_ENDPOINT environment variable is not set.';
    }

    if (hasPlaceholder(value)) {
        return 'Server misconfigured: SIP_ENDPOINT still contains placeholder markers. Use a real endpoint like sip:username@registrar.vobiz.ai (no < >).';
    }

    if (!String(value).startsWith('sip:') || !String(value).includes('@')) {
        return 'Server misconfigured: SIP_ENDPOINT must be a SIP URI like sip:username@registrar.vobiz.ai.';
    }

    return '';
}

function buildEmptyResponseXml() {
    return '<?xml version="1.0" encoding="UTF-8"?><Response></Response>';
}

function buildConfigErrorResponseXml(message) {
    return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Speak>${escapeXml(message)}</Speak>
</Response>`;
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

    let body = '';
    req.on('data', (chunk) => {
        body += chunk.toString();
    });

    req.on('end', () => {
        const parsedUrl = new URL(req.url, `http://localhost:${port}`);
        const queryParams = Object.fromEntries(parsedUrl.searchParams.entries());

        let bodyParams = {};
        try {
            bodyParams = parseBody(req, body);
        } catch (error) {
            console.error('Failed to parse request body:', error.message);
            sendText(res, 400, error.message);
            return;
        }

        const params = { ...queryParams, ...bodyParams };
        console.log(`[params] ${JSON.stringify(redactSensitiveParams(params))}`);

        if (req.method === 'POST' && parsedUrl.pathname === '/call') {
            const requestedDestination =
                params.to ||
                params.To ||
                params.destination ||
                params.Destination ||
                '';

            const formattedDestination = formatToE164(requestedDestination);
            if (!formattedDestination) {
                sendText(res, 400, 'No destination found in request body');
                return;
            }

            if (callerId && isSameNumber(formattedDestination, callerId)) {
                console.error(`Blocked self-call from /call: ${formattedDestination} == ${callerId}`);
                sendText(res, 400, 'Destination cannot be same as callerId');
                return;
            }

            lastDialedNumber = formattedDestination;
            console.log(`Outbound destination stored from app -> ${lastDialedNumber}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: true, destination: lastDialedNumber }));
            return;
        }

        if (req.method === 'POST' && parsedUrl.pathname === '/register-token') {
            const username = String(params.username || params.Username || '').trim();
            const token = String(params.token || params.Token || '').trim();

            if (!username || !token) {
                sendText(res, 400, 'username and token are required');
                return;
            }

            registeredPushTokens.set(username, token);
            console.log(`Push token registered for ${username}`);

            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: true }));
            return;
        }

        const eventName =
            params.Event ||
            params.event ||
            params.CallStatus ||
            params.callstatus ||
            '';

        if (
            parsedUrl.pathname === '/hangup' ||
            String(eventName).toLowerCase().includes('hangup')
        ) {
            console.log('Hangup event -> empty response');
            sendXml(res, buildEmptyResponseXml());
            return;
        }

        const isAnswerWebhook =
            parsedUrl.pathname === '/' || parsedUrl.pathname === '/answer';

        if (!isAnswerWebhook) {
            sendText(res, 404, 'Not found');
            return;
        }

        const callerIdError = validateCallerId(callerId);
        if (callerIdError) {
            console.error(callerIdError);
            sendXml(res, buildConfigErrorResponseXml(callerIdError));
            return;
        }

        const rawFrom = params.From || params.from || '';
        const routeType = String(params.RouteType || params.routeType || '').toLowerCase();
        const isSdkCall = rawFrom.startsWith('sip:') || routeType === 'sip';

        if (isSdkCall) {
            let destination =
                lastDialedNumber ||
                params.To ||
                params.to ||
                params.Destination ||
                params.destination ||
                '';

            if (String(destination).startsWith('sip:')) {
                const match = String(destination).match(/^sip:(.*?)@/);
                if (match && match[1]) {
                    destination = match[1];
                }
            }

            destination = formatToE164(destination);

            if (!destination) {
                if (defaultDestination) {
                    destination = formatToE164(defaultDestination);
                    console.log('No destination found, using DEFAULT_DESTINATION:', destination);
                } else {
                    console.error('No destination found for outbound call');
                    sendText(
                        res,
                        400,
                        'No destination found. Set DEFAULT_DESTINATION or POST /call first.',
                    );
                    return;
                }
            }

            if (isSameNumber(destination, callerId)) {
                console.error(`Blocked self-call: ${destination} == ${callerId}`);
                sendText(res, 400, 'Cannot call your own number');
                return;
            }

            console.log(`Outbound SDK call -> bridging to ${destination}`);

            const xmlResponse = `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Dial callerId="${escapeXml(callerId)}">
        <Number>${escapeXml(destination)}</Number>
    </Dial>
</Response>`;

            sendXml(res, xmlResponse);
            return;
        }

        const sipEndpointError = validateSipEndpoint(sipEndpoint);
        if (sipEndpointError) {
            console.error(`${sipEndpointError} Cannot route inbound calls.`);
            sendXml(res, buildConfigErrorResponseXml(sipEndpointError));
            return;
        }

        const normalizedCaller =
            rawFrom && !rawFrom.startsWith('+') && !rawFrom.startsWith('sip:')
                ? `+${rawFrom}`
                : rawFrom || 'Unknown';

        console.log(`Inbound PSTN call from ${normalizedCaller} -> routing to ${sipEndpoint}`);

        const xmlResponse = `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Dial callerId="${escapeXml(callerId)}" timeout="30">
        <User>${escapeXml(sipEndpoint)}</User>
    </Dial>
    <Speak>The call could not be connected right now. Please try again in a moment.</Speak>
</Response>`;

        sendXml(res, xmlResponse);
    });
});

server.listen(port, () => {
    console.log(`
-------------------------------------------------------
  Vobiz Backend running on port ${port}
-------------------------------------------------------
  Frontend (Web UI):
     http://localhost:${port}/client/index.html

  Flutter outbound helper:
     POST http://127.0.0.1:${port}/call

  Vobiz Answer URL:
     https://<your-ngrok-url>/answer

  Required .env values:
     CALLER_ID=+918046733542
     SIP_ENDPOINT=sip:your-endpoint-username@registrar.vobiz.ai

  Behavior:
     - App POST /call stores the outbound destination
     - /answer returns <Number> for SDK outbound calls
     - /answer returns <User> for inbound PSTN calls
-------------------------------------------------------
    `);
});
