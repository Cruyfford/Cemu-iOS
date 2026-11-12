// Minimal cubeb implementation for iOS on top of the RemoteIO audio unit.
// Upstream cubeb's AudioUnit backend uses macOS-only CoreAudio device APIs, so the iOS
// port provides just the subset of the cubeb API that Cemu's CubebAPI uses (output only).
#include <cubeb/cubeb.h>
#include <AudioToolbox/AudioToolbox.h>
#include <atomic>
#include <cstring>
#include <cstdlib>

struct cubeb
{
	int dummy;
};

struct cubeb_stream
{
	AudioComponentInstance unit = nullptr;
	cubeb_data_callback dataCb = nullptr;
	cubeb_state_callback stateCb = nullptr;
	void* user = nullptr;
	uint32_t channels = 2;
	std::atomic<float> volume{1.0f};
	bool started = false;
};

static OSStatus RenderCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp,
							   UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData)
{
	auto* stm = (cubeb_stream*)inRefCon;
	if (!ioData || ioData->mNumberBuffers == 0)
		return noErr;
	AudioBuffer& buf = ioData->mBuffers[0];
	long frames = stm->dataCb ? stm->dataCb(stm, stm->user, nullptr, buf.mData, (long)inNumberFrames) : 0;
	const size_t bytesPerFrame = stm->channels * sizeof(int16_t);
	if (frames < (long)inNumberFrames)
		memset((uint8_t*)buf.mData + frames * bytesPerFrame, 0, (inNumberFrames - frames) * bytesPerFrame);
	const float vol = stm->volume.load(std::memory_order_relaxed);
	if (vol < 0.999f)
	{
		int16_t* s = (int16_t*)buf.mData;
		const size_t n = (size_t)inNumberFrames * stm->channels;
		for (size_t i = 0; i < n; i++)
			s[i] = (int16_t)((float)s[i] * vol);
	}
	return noErr;
}

extern "C" {

int cubeb_init(cubeb** context, char const* /*context_name*/, char const* /*backend_name*/)
{
	*context = new cubeb();
	return CUBEB_OK;
}

char const* cubeb_get_backend_id(cubeb* /*context*/)
{
	return "remoteio";
}

int cubeb_get_max_channel_count(cubeb* /*context*/, uint32_t* max_channels)
{
	*max_channels = 2;
	return CUBEB_OK;
}

int cubeb_get_min_latency(cubeb* /*context*/, cubeb_stream_params* /*params*/, uint32_t* latency_frames)
{
	*latency_frames = 512;
	return CUBEB_OK;
}

int cubeb_get_preferred_sample_rate(cubeb* /*context*/, uint32_t* rate)
{
	*rate = 48000;
	return CUBEB_OK;
}

void cubeb_destroy(cubeb* context)
{
	delete context;
}

int cubeb_enumerate_devices(cubeb* /*context*/, cubeb_device_type /*devtype*/, cubeb_device_collection* collection)
{
	// only the default device exists, Cemu adds it on its own
	collection->device = nullptr;
	collection->count = 0;
	return CUBEB_OK;
}

int cubeb_device_collection_destroy(cubeb* /*context*/, cubeb_device_collection* collection)
{
	collection->device = nullptr;
	collection->count = 0;
	return CUBEB_OK;
}

int cubeb_stream_init(cubeb* /*context*/, cubeb_stream** stream, char const* /*stream_name*/,
					  cubeb_devid /*input_device*/, cubeb_stream_params* input_stream_params,
					  cubeb_devid /*output_device*/, cubeb_stream_params* output_stream_params,
					  uint32_t /*latency_frames*/, cubeb_data_callback data_callback,
					  cubeb_state_callback state_callback, void* user_ptr)
{
	if (input_stream_params || !output_stream_params)
		return CUBEB_ERROR_NOT_SUPPORTED; // microphone input is not implemented on iOS
	if (output_stream_params->format != CUBEB_SAMPLE_S16LE)
		return CUBEB_ERROR_INVALID_FORMAT;

	AudioComponentDescription desc{};
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_RemoteIO;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
	if (!comp)
		return CUBEB_ERROR;

	auto* stm = new cubeb_stream();
	if (AudioComponentInstanceNew(comp, &stm->unit) != noErr)
	{
		delete stm;
		return CUBEB_ERROR;
	}
	stm->dataCb = data_callback;
	stm->stateCb = state_callback;
	stm->user = user_ptr;
	stm->channels = output_stream_params->channels;

	AudioStreamBasicDescription fmt{};
	fmt.mSampleRate = output_stream_params->rate;
	fmt.mFormatID = kAudioFormatLinearPCM;
	fmt.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
	fmt.mChannelsPerFrame = stm->channels;
	fmt.mBitsPerChannel = 16;
	fmt.mBytesPerFrame = stm->channels * 2;
	fmt.mFramesPerPacket = 1;
	fmt.mBytesPerPacket = fmt.mBytesPerFrame;
	OSStatus r = AudioUnitSetProperty(stm->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, sizeof(fmt));

	AURenderCallbackStruct cb{};
	cb.inputProc = RenderCallback;
	cb.inputProcRefCon = stm;
	if (r == noErr)
		r = AudioUnitSetProperty(stm->unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, sizeof(cb));
	if (r == noErr)
		r = AudioUnitInitialize(stm->unit);
	if (r != noErr)
	{
		AudioComponentInstanceDispose(stm->unit);
		delete stm;
		return CUBEB_ERROR;
	}
	*stream = stm;
	return CUBEB_OK;
}

void cubeb_stream_destroy(cubeb_stream* stream)
{
	if (!stream)
		return;
	if (stream->unit)
	{
		AudioOutputUnitStop(stream->unit);
		AudioUnitUninitialize(stream->unit);
		AudioComponentInstanceDispose(stream->unit);
	}
	delete stream;
}

int cubeb_stream_start(cubeb_stream* stream)
{
	if (AudioOutputUnitStart(stream->unit) != noErr)
		return CUBEB_ERROR;
	stream->started = true;
	if (stream->stateCb)
		stream->stateCb(stream, stream->user, CUBEB_STATE_STARTED);
	return CUBEB_OK;
}

int cubeb_stream_stop(cubeb_stream* stream)
{
	AudioOutputUnitStop(stream->unit);
	stream->started = false;
	if (stream->stateCb)
		stream->stateCb(stream, stream->user, CUBEB_STATE_STOPPED);
	return CUBEB_OK;
}

int cubeb_stream_get_position(cubeb_stream* /*stream*/, uint64_t* position)
{
	*position = 0;
	return CUBEB_ERROR_NOT_SUPPORTED;
}

int cubeb_stream_get_latency(cubeb_stream* /*stream*/, uint32_t* latency)
{
	*latency = 512;
	return CUBEB_OK;
}

int cubeb_stream_set_volume(cubeb_stream* stream, float volume)
{
	stream->volume = volume < 0.0f ? 0.0f : (volume > 1.0f ? 1.0f : volume);
	return CUBEB_OK;
}

void* cubeb_stream_user_ptr(cubeb_stream* stream)
{
	return stream->user;
}

int cubeb_set_log_callback(cubeb_log_level /*log_level*/, cubeb_log_callback /*log_callback*/)
{
	return CUBEB_OK;
}

} // extern "C"
