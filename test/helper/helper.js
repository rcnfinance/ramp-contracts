module.exports.address0x = '0x0000000000000000000000000000000000000000';

module.exports.arrayToBytesOfBytes32 = (array) => {
    let bytes = '0x';
    for (let i = 0; i < array.length; i++) {
        let bytes32 = module.exports.toBytes32(array[i]).toString().replace('0x', '');
        if (bytes32.length < 64) {
            const diff = 64 - bytes32.length;
            bytes32 = '0'.repeat(diff) + bytes32;
        }
        bytes += bytes32;
    }

    return bytes;
};

module.exports.toBytes32 = (source) => {
    source = web3.toHex(source);
    const rl = 64;
    source = source.toString().replace('0x', '');
    if (source.length < rl) {
        const diff = 64 - source.length;
        source = '0'.repeat(diff) + source;
    }
    return '0x' + source;
};

module.exports.increaseTime = async (delta) => {
    await web3.currentProvider.send({ jsonrpc: '2.0', method: 'evm_increaseTime', params: [delta], id: 0 });
};

module.exports.getBlockTime = async () => {
    return (await web3.eth.getBlock('pending')).timestamp;
};

// the promiseFunction should be a function
module.exports.tryCatchRevert = async (promise, message) => {
    let headMsg = 'revert ';
    if (message === '') {
        headMsg = headMsg.slice(0, headMsg.length - 1);
    }
    try {
        if (promise instanceof Function) {
            await promise();
        } else {
            await promise;
        }
    } catch (error) {
        assert(
            error.message.search(headMsg + message) >= 0 || process.env.SOLIDITY_COVERAGE,
            'Expected a revert \'' + headMsg + message + '\', got ' + error.message + '\' instead'
        );
        return;
    }
    assert.fail('Expected throw not received');
};

module.exports.toInterestRate = (interest) => {
    return Math.floor((10000000 / interest) * 360 * 86400);
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