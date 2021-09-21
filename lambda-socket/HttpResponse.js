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
            console.log('lambda-socket -> HttpResponse -> error', error);
        }

        HttpResponse.currentEvent = null;

        return responseObj;
    }

    static getCurrentOrigin() {
        if (!HttpResponse.currentEvent.headers) {
            return null;
        }

        return HttpResponse.currentEvent.headers.origin || null
    }
}

HttpResponse.defaultResponse = {
    statusCode: 204,
    headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
        "Access-Control-Allow-Method": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "X-Prefix, Origin, Content-Type, Content-Encoding",
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
