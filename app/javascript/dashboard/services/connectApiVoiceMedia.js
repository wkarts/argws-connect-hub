function downsample(input, inputRate, outputRate = 16000) {
  if (inputRate === outputRate) return new Float32Array(input);
  if (outputRate > inputRate) return new Float32Array(input);

  const ratio = inputRate / outputRate;
  const resultLength = Math.max(1, Math.round(input.length / ratio));
  const result = new Float32Array(resultLength);
  let outputIndex = 0;
  let inputIndex = 0;

  while (outputIndex < resultLength) {
    const nextInputIndex = Math.min(
      input.length,
      Math.round((outputIndex + 1) * ratio)
    );
    let sum = 0;
    let count = 0;
    for (let i = inputIndex; i < nextInputIndex; i += 1) {
      sum += input[i];
      count += 1;
    }
    result[outputIndex] = count
      ? sum / count
      : input[Math.min(inputIndex, input.length - 1)] || 0;
    outputIndex += 1;
    inputIndex = nextInputIndex;
  }

  return result;
}

export class ConnectApiVoiceMediaSession {
  constructor({ mediaUrl, ticket }, callbacks = {}) {
    this.mediaUrl = mediaUrl;
    this.ticket = ticket;
    this.callbacks = callbacks;
    this.socket = null;
    this.stream = null;
    this.audioContext = null;
    this.source = null;
    this.processor = null;
    this.silentGain = null;
    this.playbackCursor = 0;
    this.ready = false;
    this.closed = false;
    this.micMuted = false;
  }

  setState(state) {
    if (this.callbacks.onState) this.callbacks.onState(state);
  }

  reportError(error) {
    const message = error instanceof Error ? error.message : String(error || 'Falha no áudio da chamada.');
    if (this.callbacks.onError) this.callbacks.onError(message);
    this.setState('error');
  }

  async start() {
    if (this.closed) throw new Error('A sessão de áudio já foi encerrada.');
    if (!this.ticket || !this.mediaUrl) throw new Error('Ticket de mídia da Connect|API indisponível.');
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      throw new Error('Este navegador não oferece acesso ao microfone.');
    }

    this.setState('requesting_microphone');
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          channelCount: 1,
        },
        video: false,
      });

      const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
      if (!AudioContextCtor) throw new Error('Áudio em tempo real não é suportado neste navegador.');
      this.audioContext = new AudioContextCtor();
      await this.audioContext.resume();
      this.attachMicrophone();
      await this.connectSocket();
    } catch (error) {
      this.reportError(error);
      this.stop();
      throw error;
    }
  }

  setMicMuted(muted) {
    this.micMuted = Boolean(muted);
    (this.stream && this.stream.getAudioTracks ? this.stream.getAudioTracks() : []).forEach(track => {
      track.enabled = !this.micMuted;
    });
  }

  attachMicrophone() {
    if (!this.audioContext || !this.stream) return;
    this.source = this.audioContext.createMediaStreamSource(this.stream);
    this.processor = this.audioContext.createScriptProcessor(2048, 1, 1);
    this.silentGain = this.audioContext.createGain();
    this.silentGain.gain.value = 0;

    this.processor.onaudioprocess = event => {
      if (
        !this.ready ||
        this.micMuted ||
        !this.socket ||
        this.socket.readyState !== WebSocket.OPEN ||
        !this.audioContext
      ) {
        return;
      }
      const input = event.inputBuffer.getChannelData(0);
      const pcm = downsample(input, this.audioContext.sampleRate, 16000);
      if (pcm.byteLength) this.socket.send(pcm.buffer);
    };

    this.source.connect(this.processor);
    this.processor.connect(this.silentGain);
    this.silentGain.connect(this.audioContext.destination);
  }

  connectSocket() {
    return new Promise((resolve, reject) => {
      this.setState('connecting');
      const socket = new WebSocket(this.mediaUrl);
      this.socket = socket;
      socket.binaryType = 'arraybuffer';
      let settled = false;

      const fail = error => {
        if (settled) return;
        settled = true;
        reject(error);
      };

      socket.onopen = () => {
        socket.send(JSON.stringify({ ticket: this.ticket }));
      };

      socket.onmessage = async event => {
        if (typeof event.data === 'string') {
          try {
            const message = JSON.parse(event.data);
            if (message && message.type === 'ready') {
              this.ready = true;
              this.setState('ready');
              if (!settled) {
                settled = true;
                resolve();
              }
              return;
            }
            if (message && message.type === 'error' && this.callbacks.onError) {
              this.callbacks.onError(String(message.message || 'Falha no áudio da chamada.'));
            }
          } catch (e) {
            // Mensagens de controle desconhecidas são ignoradas.
          }
          return;
        }

        try {
          let buffer = event.data;
          if (!(buffer instanceof ArrayBuffer) && buffer && buffer.arrayBuffer) {
            buffer = await buffer.arrayBuffer();
          }
          this.playIncomingPcm(buffer);
        } catch (error) {
          if (this.callbacks.onError) this.callbacks.onError(error.message || String(error));
        }
      };

      socket.onerror = () => fail(new Error('Não foi possível abrir o áudio em tempo real da chamada.'));
      socket.onclose = event => {
        this.ready = false;
        if (this.closed) return;
        const reason = event.reason ? `: ${event.reason}` : '';
        if (!settled) fail(new Error(`Áudio da chamada encerrado${reason}`));
        else this.setState('closed');
      };
    });
  }

  playIncomingPcm(buffer) {
    if (
      !this.audioContext ||
      !(buffer instanceof ArrayBuffer) ||
      buffer.byteLength === 0 ||
      buffer.byteLength % Float32Array.BYTES_PER_ELEMENT !== 0
    ) {
      return;
    }
    const samples = new Float32Array(buffer.slice(0));
    if (!samples.length) return;

    const audioBuffer = this.audioContext.createBuffer(1, samples.length, 16000);
    audioBuffer.copyToChannel(samples, 0);
    const source = this.audioContext.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(this.audioContext.destination);
    const now = this.audioContext.currentTime;
    this.playbackCursor = Math.max(this.playbackCursor, now + 0.04);
    source.start(this.playbackCursor);
    this.playbackCursor += audioBuffer.duration;
  }

  stop() {
    if (this.closed) return;
    this.closed = true;
    this.ready = false;

    if (this.processor) {
      this.processor.onaudioprocess = null;
      try { this.processor.disconnect(); } catch (e) {}
    }
    try { if (this.source) this.source.disconnect(); } catch (e) {}
    try { if (this.silentGain) this.silentGain.disconnect(); } catch (e) {}
    (this.stream && this.stream.getTracks ? this.stream.getTracks() : []).forEach(track => track.stop());

    if (this.socket && this.socket.readyState <= WebSocket.OPEN) {
      try { this.socket.close(1000, 'Sessão HUB encerrada'); } catch (e) {}
    }
    this.socket = null;
    this.stream = null;
    this.source = null;
    this.processor = null;
    this.silentGain = null;

    if (this.audioContext && this.audioContext.state !== 'closed') {
      this.audioContext.close().catch(() => undefined);
    }
    this.audioContext = null;
    this.setState('closed');
  }
}
