#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>
#import <OpenGL/glu.h>

//-----------------------------------------------------------------------------------
// AppView
//-----------------------------------------------------------------------------------
constexpr int num = 100;

@interface AppView : NSOpenGLView
{
    NSTimer*    animationTimer;
    float time;
    GLuint program;
    GLuint tex;
    GLuint framebuffer;
    GLuint posLoc;
    GLuint tex1;
}
@end

GLint compileShader(GLenum type, const char* src)
{
    auto shader = glCreateShader(type);
    //NSLog(@"src: %s", src);
    glShaderSource(shader, 1, &src, nullptr);
    glCompileShader(shader);
    GLint success = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        GLint len;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &len);
        GLchar *log = (GLchar*)malloc(len);
        glGetShaderInfoLog(shader, len, nullptr, log);
        NSLog(@"Failed to compile!: %s", log);
    }
    GLenum err = glGetError();
    if (err) {
        NSLog(@"Err Compiling: %x", err);
    }
    return shader;
}

@implementation AppView

-(void)prepareOpenGL
{
    [super prepareOpenGL];

#ifndef DEBUG
    GLint swapInterval = 1;
    [[self openGLContext] setValues:&swapInterval forParameter:NSOpenGLCPSwapInterval];
    if (swapInterval == 0)
        NSLog(@"Error: Cannot set swap interval.");
#endif
}

-(void)initialize
{
    [[self openGLContext] makeCurrentContext];
    NSLog(@"version : %s", glGetString(GL_VERSION));
    NSLog(@"vendor  : %s", glGetString(GL_VENDOR));
    NSLog(@"renderer: %s", glGetString(GL_RENDERER));
    NSLog(@"GLSL ver: %s", glGetString(GL_SHADING_LANGUAGE_VERSION));
    glEnable(GL_PROGRAM_POINT_SIZE);
    //glPointSize(10);

    program = glCreateProgram();

    glAttachShader(program,
                   compileShader(GL_VERTEX_SHADER, R"(#version 410
                                                    in vec4 position;
                                                    void main() {
                                                        gl_Position = position;
                                                    })"));

    glAttachShader(program,
                   compileShader(GL_FRAGMENT_SHADER, R"(#version 410
                                                      uniform sampler2DArray tex;
                                                      out vec4 fragColor;
                                                      void main() {
                                                          fragColor = texture(tex, vec3(0.5, 0.5, mod(floor(gl_FragCoord.x / 16.0), 2.0)));
                                                      })"));

    glLinkProgram(program);
    GLint success = 0;
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if (!success) {
        GLint len;
        glGetProgramiv(program, GL_INFO_LOG_LENGTH, &len);
        GLchar *log = (GLchar*)malloc(len);
        glGetProgramInfoLog(program, len, &len, log);
        NSLog(@"Failed to link!: %s", log);
    }

  GLint program2 = glCreateProgram();

  glAttachShader(program2,
                 compileShader(GL_VERTEX_SHADER, R"(#version 410
                                                  in vec4 position;
                                                  void main() {
                                                      gl_Position = position;
                                                  })"));

  glAttachShader(program2,
                 compileShader(GL_FRAGMENT_SHADER, R"(#version 410
                                                    uniform sampler2DArray tex;
                                                    out vec4 fragColor;
                                                    void main() {
                                                        fragColor = texture(tex, vec3(0.5, 0.5, 0)).bgra;
                                                    })"));

  glLinkProgram(program2);
  glGetProgramiv(program2, GL_LINK_STATUS, &success);
  if (!success) {
      GLint len;
      glGetProgramiv(program2, GL_INFO_LOG_LENGTH, &len);
      GLchar *log = (GLchar*)malloc(len);
      glGetProgramInfoLog(program2, len, &len, log);
      NSLog(@"Failed to link!: %s", log);
  }


    posLoc = glGetAttribLocation(program, "position");
    GLuint va;
    glGenVertexArrays(1, &va);
    glBindVertexArray(va);
    
    GLuint buf;
    glGenBuffers(1, &buf);
    static const float quad[] = {
        -1, -1,
         1, -1,
        -1,  1,
        -1,  1,
         1, -1,
         1,  1,
    };
    glBindBuffer(GL_ARRAY_BUFFER, buf);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
    glEnableVertexAttribArray(posLoc);
    glVertexAttribPointer(posLoc, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
    
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D_ARRAY, tex);
    uint8_t color[] = {0, 0, 255, 255, 0, 0, 0, 0};
    glTexImage3D(GL_TEXTURE_2D_ARRAY, 0, GL_RGBA, 1, 1, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, &color);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, tex, 0, 1);

    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAX_LEVEL, 0);
    glViewport(0, 0, 1, 1);
    glUseProgram(program2);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAX_LEVEL, 1);

    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    GLenum err = glGetError();
    if (err) {
        NSLog(@"Err Initializing: %x", err);
    }
}

-(void)updateAndDrawDemoView
{
    time += 0.016;
    
    [[self openGLContext] makeCurrentContext];
    GLsizei width  = (float)self.bounds.size.width;
    GLsizei height = (float)self.bounds.size.height;
    glViewport(0, 0, width, height);
    float c = fmod(time, 1.0f);
    glClearColor(c, c, c, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(program);
    glBindTexture(GL_TEXTURE_2D_ARRAY, tex);
    glDrawArrays(GL_TRIANGLES, 0, 6);

    GLenum err = glGetError();
    if (err) {
        NSLog(@"Err Drawing: %x", err);
    }

    // Present
    [[self openGLContext] flushBuffer];

    if (!animationTimer)
        animationTimer = [NSTimer scheduledTimerWithTimeInterval:0.017 target:self selector:@selector(animationTimerFired:) userInfo:nil repeats:YES];
}

-(void)reshape                              { [super reshape]; [[self openGLContext] update]; [self updateAndDrawDemoView]; }
-(void)drawRect:(NSRect)bounds              { [self updateAndDrawDemoView]; }
-(void)animationTimerFired:(NSTimer*)timer  { [self setNeedsDisplay:YES]; }
-(void)dealloc                              { animationTimer = nil; }

@end

//-----------------------------------------------------------------------------------
// AppDelegate
//-----------------------------------------------------------------------------------

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, readonly) NSWindow* window;
@end

@implementation AppDelegate
@synthesize window = _window;

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
    return YES;
}

-(NSWindow*)window
{
    if (_window != nil)
        return (_window);

    NSRect viewRect = NSMakeRect(100.0, 100.0, 100.0 + 1280.0, 100 + 720.0);

    _window = [[NSWindow alloc] initWithContentRect:viewRect styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:YES];
    [_window setTitle:@"OpenGL Example"];
    [_window setAcceptsMouseMovedEvents:YES];
    [_window setOpaque:YES];
    [_window makeKeyAndOrderFront:NSApp];

    return (_window);
}

-(void)setupMenu
{
    NSMenu* mainMenuBar = [[NSMenu alloc] init];
    NSMenu* appMenu;
    NSMenuItem* menuItem;

    appMenu = [[NSMenu alloc] initWithTitle:@"OpenGL Example"];
    menuItem = [appMenu addItemWithTitle:@"OpenGL Example" action:@selector(terminate:) keyEquivalent:@"q"];
    [menuItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];

    menuItem = [[NSMenuItem alloc] init];
    [menuItem setSubmenu:appMenu];

    [mainMenuBar addItem:menuItem];

    appMenu = nil;
    [NSApp setMainMenu:mainMenuBar];
}

-(void)dealloc
{
    _window = nil;
}

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Make the application a foreground application (else it won't receive keyboard events)
    ProcessSerialNumber psn = {0, kCurrentProcess};
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);

    // Menu
    [self setupMenu];

    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 32,
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        0
    };

    NSOpenGLPixelFormat* format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    AppView* view = [[AppView alloc] initWithFrame:self.window.frame pixelFormat:format];
    format = nil;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1070
    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_6)
        [view setWantsBestResolutionOpenGLSurface:YES];
#endif // MAC_OS_X_VERSION_MAX_ALLOWED >= 1070
    [self.window setContentView:view];

    if ([view openGLContext] == nil)
        NSLog(@"No OpenGL Context!");

    [view initialize];
}

@end

//-----------------------------------------------------------------------------------
// Application main() function
//-----------------------------------------------------------------------------------

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        NSApp = [NSApplication sharedApplication];
        AppDelegate* delegate = [[AppDelegate alloc] init];
        [[NSApplication sharedApplication] setDelegate:delegate];
        [NSApp run];
    }
    return NSApplicationMain(argc, argv);
}
