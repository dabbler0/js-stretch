#define BUILDING_NODE_EXTENSION

#include <node.h>
#include <fftw3.h>
#include <stdlib.h>
#include <cstdio>

#define GET_ARG(ARGS,I,TYPE,VAR)                                        \
    if (ARGS.Length() <= (I) || !ARGS[I]->Is##TYPE())                   \
        return ThrowException(Exception::TypeError(                     \
            String::New("Argument " #I ": " #TYPE " required" ))) ;     \
    Local<TYPE> VAR = Local<TYPE>::Cast(ARGS[I]) ;

/*
 * Derviative of https://github.com/bpadalino/node_fftw by Brian Padalino
 * Adapted for nodejs >=5.x by Anthony Bau
 */

using namespace v8;
using namespace node;

class fftw3 : ObjectWrap {
    
    private:
        int length ;
        fftw_plan plan ;
        fftw_complex *in ;
        fftw_complex *out ;
        
    public:
        
        // Function Templates
        static Persistent<Function> constructor ;
        
        // Initialization
        static void Initialize(Handle<Object> target) {
            HandleScope scope ;
            
            // The New passed in here refers to the static Handle<Value> New() below
            Local<FunctionTemplate> t = FunctionTemplate::New(New) ;
            
            // I am not 100% positive what this does just yet
            t->InstanceTemplate()->SetInternalFieldCount(4) ;
            
            // Set the class name for the function table lookups
            t->SetClassName(String::NewSymbol("fftw3")) ;
            
            // Attach the "execute" function
            // to the publicly-visible prototype.
            t->PrototypeTemplate()->Set(String::NewSymbol("execute"),
                  FunctionTemplate::New(execute)->GetFunction());

            constructor = Persistent<Function>::New(t->GetFunction());
            
            // Export a symbol that we can use to new() in Javascript, and associate
            // the action to take with static Handle<Value> New(), which will create
            // a new object for us
            target->Set(String::NewSymbol("Plan"), constructor) ;
        }
        
        // State holding
        // length: the window size
        // mode: FFTW_FORWARD or FFTW_BACKWARD
        fftw3(int _length, int mode) {
            length = _length ;
            in = (fftw_complex*)fftw_malloc(sizeof(fftw_complex)*length) ;
            out = (fftw_complex*)fftw_malloc(sizeof(fftw_complex)*length) ;
            plan = fftw_plan_dft_1d(length, in, out, mode, FFTW_ESTIMATE);
        }
        
        // Any extra deletes
        ~fftw3() {
            fftw_destroy_plan(plan) ;
            fftw_free(in) ;
            fftw_free(out) ;
        }
        
        // Execute the plan!
        void execute() {
            fftw_execute(plan) ;
        }
        
        static Handle<Value> New(const Arguments &args) {
            HandleScope scope ;
            if (args.IsConstructCall()) {
              GET_ARG(args,0,Number,num) ;
              fftw3 *design = new fftw3((int)(num->NumberValue()), ((bool)args[1]->BooleanValue() ? FFTW_FORWARD : FFTW_BACKWARD)) ;
              design->Wrap(args.This()) ;
              return args.This() ;
            }
            else {
              const int argc = 2;
              Local<Value> argv[argc] = { args[0], args[1] };
              return scope.Close(constructor->NewInstance(argc, argv));
            }
        }
        
        // The baton that we want to keep and pass around
        struct baton_t {
            fftw3 *design ;
            Persistent<Function> cb ;
        } ;
        
        // Setting up the event loop
        static Handle<Value> execute(const Arguments &args) {
            HandleScope scope ;
            
            GET_ARG(args,0,Array,array) ;
            GET_ARG(args,1,Function,cb) ;
            
            fftw3 *design = ObjectWrap::Unwrap<fftw3>(args.This()) ;
            
            // Save the baton for later
            baton_t *baton = new baton_t() ;
            baton->design = design ;
            
            char errorMessage[1000];
            sprintf(errorMessage, "Array length not equal to design length (array length %d, design length %d)", array->Length(), 2 * (design->length)) ;
            // Make sure we're of the right size
            if( array->Length() != 2*(design->length) ) {
                return ThrowException(Exception::Error(String::New(errorMessage)));
            } else {
                // Copy the array to the input
                for(int i=0; i< design->length ; i+=1 ) {
                    design->in[i][0] = array->Get(2*i)->NumberValue() ;
                    design->in[i][1] = array->Get(2*i+1)->NumberValue() ;
                }
            }
            
            // Get the callback persistent
            baton->cb = Persistent<Function>::New(cb) ;

            
            // Increment reference count for object
            design->Ref() ;
            
            // Construct a passable "baton" for libuv events
            uv_work_t *req = new uv_work_t;
            req->data = baton;

            // Setup the event structure, passing the baton
            uv_queue_work(uv_default_loop(), req, UV_execute, UV_callback);

            // Should no longer be necessary:
            // uv_ref((uv_handle_t*) &req);
            
            return Undefined() ;
        }
        
        // The long operation
        static void UV_execute (uv_work_t *req) {
            // Cast data to the baton that we're passing
            baton_t *baton = static_cast<baton_t *>(req->data) ;
            
            // Long operation
            baton->design->execute() ;
        }
        
        // Callback after the long operation
        static void UV_callback (uv_work_t *req, int status) {
            if (status) return;

            HandleScope scope ;
            baton_t *baton = static_cast<baton_t *>(req->data) ;
            
            // Create the return arguments
            Local<Value> argv[1] ;
            Local<Array> result = Array::New(baton->design->length*2) ;
            
            // Copy the output of the design into the new array
            for(int i = 0 ; i < baton->design->length ; i+=1 ) {
                result->Set(2*i, Number::New(baton->design->out[i][0]) ) ;
                result->Set(2*i+1, Number::New(baton->design->out[i][1]) ) ;
            }
            
            // We're now done with the object
            // Decrement reference count for object
            baton->design->Unref() ;
            
            TryCatch try_catch ;
            
            argv[0] = result ;
            
            // Call the callback
            baton->cb->Call(Context::GetCurrent()->Global(), 1, argv ) ;
            
            // Any exceptions?
            if( try_catch.HasCaught() ) {
                FatalException(try_catch) ;
            }
            
            // Let it be known, we are done!
            baton->cb.Dispose() ;
            
            // Get rid of the baton since we're done with the race
            delete baton ;
        }
} ;

Persistent<Function> fftw3::constructor ;

extern "C" {
    void init (Handle<Object> target) 
    {
        fftw3::Initialize(target) ;
    }
    
    NODE_MODULE( fftw3, init ) ;
}
