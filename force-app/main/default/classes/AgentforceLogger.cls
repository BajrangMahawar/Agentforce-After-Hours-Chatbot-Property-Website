/**
 * One place every Agentforce action logs through, so a single search over a
 * debug log follows a conversation across all four actions and the trigger.
 *
 * Every line looks like:  SITEVISIT | GET_PROPERTIES ENTRY | city=Pune ...
 * so filtering on SITEVISIT gives the whole flow, and filtering on the class
 * tag narrows it to one action.
 */
public without sharing class AgentforceLogger {
    public static final String LOG_TAG = 'SITEVISIT';

    public static void log(String source, String step, String detail) {
        System.debug(LoggingLevel.INFO, LOG_TAG + ' | ' + source + ' ' + step + ' | ' + detail);
    }

    /** Keeps null and empty distinguishable, which matters for optional inputs. */
    public static String show(Object value) {
        if (value == null) {
            return '<null>';
        }
        String text = String.valueOf(value);
        return text == '' ? '<blank>' : text;
    }

    /** Renders an instant as UTC, the form worth comparing across timezones. */
    public static String utc(Datetime value) {
        return value == null ? '<null>' : value.format('yyyy-MM-dd HH:mm', 'GMT') + ' UTC';
    }

    /**
     * Logs an exception with everything needed to identify it: the type, the
     * message, the line, the stack, and for DML the per-row field errors that
     * a plain getMessage() leaves out.
     */
    public static void logException(String source, String step, Exception e) {
        log(source, step, e.getTypeName() + ': ' + e.getMessage());
        log(source, step, 'line ' + e.getLineNumber() + ' | stack: ' + e.getStackTraceString());
        if (e instanceof DmlException) {
            DmlException dmlError = (DmlException) e;
            for (Integer i = 0; i < dmlError.getNumDml(); i++) {
                log(source, step, 'DML[' + i + '] ' + dmlError.getDmlStatusCode(i) +
                    ' on fields ' + dmlError.getDmlFieldNames(i) + ': ' + dmlError.getDmlMessage(i));
            }
        }
    }

    /** The running context, logged once per action so a timezone bug is visible. */
    public static void logContext(String source, Integer requestCount) {
        log(source, 'ENTRY', 'requests=' + requestCount +
            ' runningUser=' + UserInfo.getUserName() +
            ' userTimeZone=' + UserInfo.getTimeZone().getID() +
            ' now=' + utc(Datetime.now()));
    }
}
