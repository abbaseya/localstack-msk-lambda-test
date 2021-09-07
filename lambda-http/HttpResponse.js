class HttpResponse {
    /**
     * Use response object for return value or in callback
     * @param responseObject
     * @return {{ statusCode: number, headers: {"Access-Control-Expose-Headers": string, "Access-Control-Allow-Method": string, "Access-Control-Allow-Origin": string, "Access-Control-Allow-Credentials": boolean, "Access-Control-Allow-Headers": string, "Content-Type": string}, error: Object, body: string}}
     */
    static createResponseObject(responseObject) {
        if (HttpResponse.currentEvent) {
            let origin = HttpResponse.getCurrentOrigin();
            if (origin) {
                HttpResponse.defaultResponse.headers["Access-Control-Allow-Origin"] = origin;
            } else {
                HttpResponse.defaultResponse.headers["Access-Control-Allow-Origin"] = '*';
            }
        }
        return Object.assign({}, HttpResponse.defaultResponse, responseObject);
    }

    /**
     *
     * @param [body]
     * @param [statusCode]
     * @param [error]
     * @param errorInfo
     * @return {{statusCode: number, headers: {"Access-Control-Expose-Headers": string, "Access-Control-Allow-Method": string, "Access-Control-Allow-Origin": string, "Access-Control-Allow-Credentials": boolean, "Access-Control-Allow-Headers": string, "Content-Type": string}, error: Object, body: string}}
     */
    static handleResponse(body = '', statusCode = 200, error = null, errorInfo = {}) {
        if (typeof body === 'string') {
            body = {
                message: body
            }
        }

        let responseObj = HttpResponse.createResponseObject({
            statusCode: statusCode,
            body: JSON.stringify(body)
        });

        if (statusCode === 204) {
            responseObj.body = '';
        }

        if (error) {
            HttpResponse.informError(error, errorInfo, body, responseObj)
        }

        HttpResponse.currentEvent = null;

        return responseObj;
    }

    static informError(error, errorInfo = {}, responseBody = '', responseObj = {}) {
        let infoObject = {};
        infoObject.error = error;
        infoObject.errorInfo = errorInfo;
        infoObject.responseBody = responseBody;
        infoObject.responseObj = responseObj;

        if (HttpResponse.currentEvent !== null && typeof HttpResponse.currentEvent === 'object') {
            if (!!HttpResponse.currentEvent.body) {
                infoObject.base64Body = HttpResponse.base64Encode(HttpResponse.currentEvent.body);
                HttpResponse.currentEvent.body = '-';
                HttpResponse.currentEvent.requestContext = '-';
                HttpResponse.currentEvent.multiValueHeaders = '-';
            }
        }
        infoObject.currentEvent = HttpResponse.currentEvent;

        console.log(infoObject);
    }

    static parseRequest(event, expectResult = HttpResponse.resultTypeObject) {
        event = event || HttpResponse.currentEvent;
        let data = null;
        try {
            data = JSON.parse(event.body);
            return data;
        } catch (e) {
            data = null;
        }

        if (data) {
            try {
                data = JSON.parse(data);
            } catch (e) {
                if (expectResult === HttpResponse.resultTypeObject) {
                    data = HttpResponse.fixBrokenJsonObjectString(data);
                    data = JSON.parse(data);
                } else {
                    throw new Error('other than HttpResponse.resultTypeObject are not implemented, only object type can be fixed right now');
                }
            }
        }

        return data;
    }

    static getCurrentOrigin() {
        if (!HttpResponse.currentEvent.headers) {
            return null;
        }

        return HttpResponse.currentEvent.headers.origin || null
    }

    static fixBrokenJsonObjectString(jsonString) {
        const regex = /[^}]*$/g;
        let point = jsonString.search(regex);
        return point ? jsonString.substr(0, point) : jsonString;
    }

    static base64Encode(binary, safe = true) {
        return Buffer.from(safe ? unescape(encodeURIComponent(binary)) : binary).toString('base64')
    }

    static base64Decode(base64, safe = true) {
        base64 = Buffer.from(base64, 'base64').toString()
        return safe ? decodeURIComponent(escape(base64)) : base64;
    }

    static base64DecodeUnicode(base64) {
        // Going backwards: from bytestream, to percent-encoding, to original string.
        return decodeURIComponent(Buffer.from(base64, 'base64').toString().split('').map(function (c) {
            return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
        }).join(''));
    }
}

HttpResponse.defaultResponse = {
    statusCode: 204,
    headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
        "Access-Control-Allow-Method": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "X-Prefix, Origin, Content-Type",
        "Access-Control-Expose-Headers": "X-Result, X-Error",
        'Content-Type': 'application/json'
    },
    body: ''
};
HttpResponse.statusCodes = {
    'ok': 200,
    'badRequest': 400,
    'error': 500,
};
HttpResponse.currentEvent = null;
HttpResponse.resultTypeObject = 'object';

module.exports = HttpResponse;
