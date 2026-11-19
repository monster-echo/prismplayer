import { rcp } from '@kit.RemoteCommunicationKit';

export interface HttpRequestOptions {
  method?: 'GET' | 'POST' | 'HEAD';
  headers?: rcp.RequestHeaders;
  body?: string;
  allowInsecureTls?: boolean;
  timeoutMs?: number;
}

export interface HttpTextResponse {
  statusCode: number;
  body: string;
}

export class HttpHelper {
  private static session: rcp.Session | null = null;

  private static getSession(): rcp.Session {
    if (!HttpHelper.session) {
      HttpHelper.session = rcp.createSession();
    }
    return HttpHelper.session;
  }

  static async requestText(url: string, options?: HttpRequestOptions): Promise<HttpTextResponse> {
    const method = options?.method || 'GET';
    const req = new rcp.Request(url, method);
    if (options?.headers) {
      req.headers = options.headers;
    }
    if (options?.body) {
      req.content = options.body;
    }
    const timeout = options?.timeoutMs || 12000;
    if (options?.allowInsecureTls) {
      req.configuration = {
        security: { remoteValidation: 'skip' },
        transfer: { timeout: { connectMs: Math.min(8000, timeout), transferMs: timeout } }
      };
    } else {
      req.configuration = {
        transfer: { timeout: { connectMs: Math.min(8000, timeout), transferMs: timeout } }
      };
    }
    const resp = await HttpHelper.getSession().fetch(req);
    return {
      statusCode: resp.statusCode,
      body: resp.toString() || ''
    };
  }
}
