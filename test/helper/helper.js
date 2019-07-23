module.exports.address0x = '0x0000000000000000000000000000000000000000';

module.exports.toBytes32 = (source) => {
    source = web3.utils.toHex(source);
    const rl = 64;
    source = source.toString().replace('0x', '');
    if (source.length < rl) {
        const diff = 64 - source.length;
        source = '0'.repeat(diff) + source;
    }
    return '0x' + source;
};

module.exports.getBlockTime = async () => {
    return (await web3.eth.getBlock('pending')).timestamp;
};

module.exports.toEvent = async (promise, ...events) => {
    const logs = (await promise).logs;
    let eventObjs = events.map(event => logs.find(log => log.event === event));
    if (eventObjs.length === 0 || eventObjs.some(x => x === undefined)) {
        assert.fail('The event dont find');
    }
    eventObjs = eventObjs.map(x => x.args);
    return (eventObjs.length === 1) ? eventObjs[0] : eventObjs;
}