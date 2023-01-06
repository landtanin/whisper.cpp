package whisper

import (
	"fmt"
)

///////////////////////////////////////////////////////////////////////////////
// CGO

/*
#include <whisper.h>
*/
import "C"

///////////////////////////////////////////////////////////////////////////////
// PUBLIC METHODS

func (p *Params) SetTranslate(v bool) {
	p.translate = toBool(v)
}

func (p *Params) SetNoContext(v bool) {
	p.no_context = toBool(v)
}

func (p *Params) SetSingleSegment(v bool) {
	p.single_segment = toBool(v)
}

func (p *Params) SetPrintSpecial(v bool) {
	p.print_special = toBool(v)
}

func (p *Params) SetPrintProgress(v bool) {
	p.print_progress = toBool(v)
}

func (p *Params) SetPrintRealtime(v bool) {
	p.print_realtime = toBool(v)
}

func (p *Params) SetPrintTimestamps(v bool) {
	p.print_timestamps = toBool(v)
}

func (p *Params) SetSpeedup(v bool) {
	p.speed_up = toBool(v)
}

func (p *Params) SetLanguage(lang int) error {
	str := C.whisper_lang_str(C.int(lang))
	if str == nil {
		return ErrInvalidLanguage
	} else {
		p.language = str
	}
	return nil
}

func (p *Params) Language() int {
	if p.language == nil {
		return -1
	}
	return int(C.whisper_lang_id(p.language))
}

func (p *Params) SetThreads(threads int) {
	p.n_threads = C.int(threads)
}

func (p *Params) SetOffset(offset_ms int) {
	p.offset_ms = C.int(offset_ms)
}

func (p *Params) SetDuration(duration_ms int) {
	p.duration_ms = C.int(duration_ms)
}

///////////////////////////////////////////////////////////////////////////////
// PRIVATE METHODS

func toBool(v bool) C.bool {
	if v {
		return C.bool(true)
	}
	return C.bool(false)
}

///////////////////////////////////////////////////////////////////////////////
// STRINGIFY

func (p *Params) String() string {
	str := "<whisper.params"
	str += fmt.Sprintf(" strategy=%v", p.strategy)
	str += fmt.Sprintf(" n_threads=%d", p.n_threads)
	if p.language != nil {
		str += fmt.Sprintf(" language=%s", C.GoString(p.language))
	}
	str += fmt.Sprintf(" n_max_text_ctx=%d", p.n_max_text_ctx)
	str += fmt.Sprintf(" offset_ms=%d", p.offset_ms)
	str += fmt.Sprintf(" duration_ms=%d", p.duration_ms)
	if p.translate {
		str += " translate"
	}
	if p.no_context {
		str += " no_context"
	}
	if p.single_segment {
		str += " single_segment"
	}
	if p.print_special {
		str += " print_special"
	}
	if p.print_progress {
		str += " print_progress"
	}
	if p.print_realtime {
		str += " print_realtime"
	}
	if p.print_timestamps {
		str += " print_timestamps"
	}
	if p.token_timestamps {
		str += " token_timestamps"
	}
	if p.speed_up {
		str += " speed_up"
	}

	return str + ">"
}
