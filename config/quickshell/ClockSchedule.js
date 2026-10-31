// Qt date formats quote literal text. Only unquoted seconds/milliseconds need
// the existing one-second cadence; all other formats update on the next minute.
function delay(format, milliseconds) {
    let tokens = String(format || "").replace(/'([^']|'')*'/g, "");
    let period = /[sz]/.test(tokens) ? 1000 : 60000;
    return period - (milliseconds % period);
}
