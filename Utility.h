////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2005 Jeremy Jurksztowicz
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software 
// and associated documentation files (the "Software"), to deal in the Software without restriction, 
// including without limitation the rights to use, copy, modify, merge, publish, distribute, 
// sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is 
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or 
// substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT 
// NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, 
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef _ark_Utility_h                                        
#define _ark_Utility_h

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Include Files
//
#include <stdexcept>
#include <string>
#include <iostream>
#include <sstream>
#include <limits>
#include <boost/thread/mutex.hpp>

// NOTE: Debugging is ON.
#define DEBUG 1
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// SOURCE_LOC
#if DEBUG
	#define _SL_UTIL_1(x)   #x
	#define _SL_UTIL_2(x)   _SL_UTIL_1(x)
	#define _SL_UTIL        _SL_UTIL_2(__LINE__)

	#define SOURCE_LOC __FILE__ ":" _SL_UTIL
#else
	#define SOURCE_LOC (void*)0
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Exception Utility
#define CATCH_AND_REPORT \
	catch(std::exception& err) { \
		std::cerr << "Exception caught : " << err.what() << " : " << SOURCE_LOC << std::endl; \
	} \
	catch(...) { \
		std::cerr << "Exception caught : " << SOURCE_LOC << std::endl; \
	} 

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#if DEBUG
	#define ERR_LOCATION std::string
	namespace ark {
	static inline std::string _locationParam (ERR_LOCATION l) { return l; }
	}
#else
	#define ERR_LOCATION void *
	namespace ark {
	static inline std::string _locationParam (ERR_LOCATION l) { return std::string(); }
	}
#endif

namespace ark {

/// Raised when an operation could not complete because of no room available in some queue.
template<typename T> struct Overflow_Template : public std::overflow_error 
{
	T message;
	
	Overflow_Template (ERR_LOCATION loc, T const& msg) throw():
		std::overflow_error(_locationParam(loc)), message(msg) { }
		
	virtual ~Overflow_Template ( ) throw() { }
};

/// Raised when an operation cannot complete because there is not enough data in some queue.
struct Underflow : public std::underflow_error
{
	Underflow (ERR_LOCATION loc): std::underflow_error(_locationParam(loc)) { }
	virtual ~Underflow ( ) throw() { }
};

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Useful named constant numbers.
//
const unsigned ONE_HUNDRED			= 100;
const unsigned ONE_THOUSAND			= 1000;
const unsigned TEN_THOUSAND			= 10000;
const unsigned ONE_HUNDRED_THOUSAND = 100000;
const unsigned ONE_MILLION			= 1000000;
const unsigned TEN_MILLION			= 10000000;
const unsigned ONE_HUNDRED_MILLION	= 100000000;
const unsigned ONE_BILLION			= 1000000000;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Simple logging system with a threshold to control specific text outputs.
//
#ifndef ARK_LOG_THRESHOLD
#define ARK_LOG_THRESHOLD 1
#endif

inline void Log(std::string msg, unsigned thresh = 1, bool fl = true) // Flush line?
{
	static boost::mutex _logMutex;
	if(thresh >= ARK_LOG_THRESHOLD) {
		boost::mutex::scoped_lock lck(_logMutex);
		std::cout << msg;
		if(fl) std::cout << std::endl;
	}
}

/// A few default logging levels, to fine tune output. You can use a level with a midifier between
/// 1 and 9, such as NORMAL_LOG + 5 if you want extreme control over output.
enum {
	LOG_MIN			= 1,
	LOG_TRACE		= 10,
	LOG_NORMAL		= 20,
	LOG_HIGH		= 30,
	LOG_MAX			= 40 // std::numeric_limits<unsigned>::max() - 1
};

} // END namespace ark

#endif // _ark_Utility_h