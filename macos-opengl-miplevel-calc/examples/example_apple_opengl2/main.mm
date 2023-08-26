#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>
#import <OpenGL/glu.h>

#import <sstream>
#import <vector>

//-----------------------------------------------------------------------------------
// AppView
//-----------------------------------------------------------------------------------
constexpr int num = 100;

@interface AppView : NSOpenGLView
{
    NSTimer*    animationTimer;
    float time;
    GLuint texProgram;
    GLuint mipProgram;
    GLuint tex;
  GLint matLocation0;
  GLint matLocation1;
  GLint texMatLocation0;
  GLint texMatLocation1;
}
@end

void checkError(const char *msg) {
  GLenum err = glGetError();
  if (err) {
      NSLog(@"Err %s: %x", msg, err);
      exit(1);
  }
}

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
    checkError("compiling");
    return shader;
}

void linkProgram(GLuint program) {
  glLinkProgram(program);
  GLint success = 0;
  glGetProgramiv(program, GL_LINK_STATUS, &success);
  if (!success) {
      GLint len;
      glGetProgramiv(program, GL_INFO_LOG_LENGTH, &len);
      GLchar *log = (GLchar*)malloc(len);
      glGetProgramInfoLog(program, len, &len, log);
      NSLog(@"Failed to link!: %s", log);
      exit(1);
  }
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

  GLint maxVertexAttribs = 0;
  glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, &maxVertexAttribs);
  NSLog(@"MAX_VERTEX_ATTRIBS: %d", maxVertexAttribs);

  checkError("getString");

  texProgram = glCreateProgram();
  mipProgram = glCreateProgram();



  GLuint vs = compileShader(GL_VERTEX_SHADER,
  R"(#version 410
  uniform mat4 u_worldViewProjection;
  uniform mat3 u_texMat;

  layout(location = 0) in vec2 p;
  out vec2 v_texCoord;

  void main() {
    v_texCoord = (u_texMat * vec3(p, 1)).xy;
    gl_Position = u_worldViewProjection * vec4(p, 0, 1);
  }
  )");



  glAttachShader(texProgram, vs);
  glAttachShader(texProgram,
                 compileShader(GL_FRAGMENT_SHADER,
                                                    R"(#version 410
                                                    precision highp float;

                                                    in vec2 v_texCoord;

                                                    uniform sampler2D u_tex;

                                                    out vec4 outColor;

                                                    void main() {
                                                    outColor = texture(u_tex, v_texCoord);
                                                    }
                                                    )"));

  linkProgram(texProgram);

  glAttachShader(mipProgram, vs);
  glAttachShader(mipProgram,
                 compileShader(GL_FRAGMENT_SHADER, R"(#version 410
                                                    precision highp float;

                                                    in vec2 v_texCoord;

                                                    out vec4 outColor;

                                                    const vec4 colors[8] = vec4[8](
                                                    vec4(  1,   0,   0, 1), // 0: red
                                                    vec4(  1,   1,   0, 1), // 1: yellow
                                                    vec4(  0,   1,   0, 1), // 2: green
                                                    vec4(  0,   1,   1, 1), // 3: cyan
                                                    vec4(  0,   0,   1, 1), // 4: blue
                                                    vec4(  1,   0,   1, 1), // 5: magenta
                                                    vec4(0.5, 0.5, 0.5, 1), // 6: gray
                                                    vec4(  1,   1,   1, 1));// 7: white

                                                    void main() {
                                                    vec2 dx = dFdx(v_texCoord);
                                                    vec2 dy = dFdy(v_texCoord);
                                                    float deltaMaxSq = max(dot(dx, dx), dot(dy, dy));
                                                    float mipLevel = 0.5 * log2(deltaMaxSq);

                                                    // mipLevel = mod(gl_FragCoord.x / 16.0, 8.0);  // comment in to test we can use the colors

                                                    outColor = colors[int(mipLevel)];

                                                    // outColor = vec4(mipLevel / 7.0, 0, 0, 1);  // comment in to visualize another way
                                                    // outColor = vec4(fract(v_texCoord), 0, 1);  // comment in to visualize texcoord
                                                    }
                                                    )"));

  linkProgram(mipProgram);

  matLocation0 = glGetUniformLocation(texProgram, "u_worldViewProjection");
  matLocation1 = glGetUniformLocation(mipProgram, "u_worldViewProjection");
  texMatLocation0 = glGetUniformLocation(texProgram, "u_texMat");
  texMatLocation1 = glGetUniformLocation(mipProgram, "u_texMat");

  checkError("programs");

  glGenTextures(1, &tex);
  glBindTexture(GL_TEXTURE_2D, tex);
  for (int i = 0; i < 8; ++i) {
    int size = 1 << (7 - i);
    int c = i + 1;
    uint32_t color =
    (((c & 0x1) ? 255 : 0) << 0) |
    (((c & 0x2) ? 255 : 0) << 8) |
    (((c & 0x4) ? 255 : 0) << 16) |
    (255 << 24) ;
    std::vector<uint32_t> colors(size * size, color);
    NSLog(@"level: %d, size: %d", i, size);
    glTexImage2D(GL_TEXTURE_2D, i, GL_RGBA8, size, size, 0, GL_RGBA, GL_UNSIGNED_BYTE, colors.data());
  }
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST_MIPMAP_NEAREST);
  checkError("textures");

  GLuint va;
  glGenVertexArrays(1, &va);
  glBindVertexArray(va);

  GLuint buf;
  glGenBuffers(1, &buf);
  static const float quad[] = {
       0,  0,
       1,  0,
       0,  1,
       0,  1,
       1,  0,
       1,  1,
  };
  glBindBuffer(GL_ARRAY_BUFFER, buf);
  glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
}

-(void)updateAndDrawDemoView
{
    time += 0.016;
    
    [[self openGLContext] makeCurrentContext];
    GLsizei width  = (float)self.bounds.size.width;
    GLsizei height = (float)self.bounds.size.height;
    glViewport(0, 0, width, height);
    glClearColor(0.3, 0.3, 0.3, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    checkError("clear");

    glUseProgram(texProgram);
    glBindTexture(GL_TEXTURE_2D, tex);

    float s = 1 + 127 * (sin(time) * 0.5 + 0.5);
    float tmat[9] = {
      s, 0, 0,
      0, s, 0,
      0, 0, 1,
    };
    float mat0[16] = {
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
    -1.01, -0.5, 0, 1,
    };
    glUniformMatrix3fv(texMatLocation0, 1, false, tmat);
    glUniformMatrix4fv(matLocation0, 1, false, mat0);
    glDrawArrays(GL_TRIANGLES, 0, 6);

    checkError("draw tex");

    glUseProgram(mipProgram);
    float mat1[16] = {
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0.01, -0.5, 0, 1,
    };
    glUniformMatrix3fv(texMatLocation1, 1, false, tmat);
    glUniformMatrix4fv(matLocation1, 1, false, mat1);
    glDrawArrays(GL_TRIANGLES, 0, 6);

    checkError("draw mip");

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
